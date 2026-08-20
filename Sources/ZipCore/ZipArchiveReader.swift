import Foundation

struct ZipArchiveReader {
    private struct DirectoryInfo {
        let entryCount: UInt64
        let offset: UInt64
        let size: UInt64
    }

    private struct AESExtra {
        let version: UInt16
        let strength: WinZipAESStrength
        let actualMethod: UInt16
    }

    private struct EncryptedLayout {
        let ciphertextOffset: UInt64
        let ciphertextSize: UInt64
        let authentication: Data
    }

    private let source: any ArchiveByteSource
    let records: [ZipRecord]

    init(data: Data) throws {
        try self.init(source: DataArchiveSource(data: data), cancellation: nil)
    }

    init(url: URL, cancellation: ZipOperationCancellation? = nil) throws {
        try self.init(source: FileArchiveSource(url: url), cancellation: cancellation)
    }

    private init(
        source: any ArchiveByteSource,
        cancellation: ZipOperationCancellation?
    ) throws {
        self.source = source
        try cancellation?.check()
        let parsed = try Self.parseRecords(source, cancellation: cancellation)
        var paths = Set<String>()
        for record in parsed where !paths.insert(record.path).inserted {
            throw ZipError.duplicateEntry(record.path)
        }
        records = parsed
    }

    func validateEncryptedEntries(
        _ records: [ZipRecord],
        password: String?,
        cancellation: ZipOperationCancellation? = nil
    ) throws {
        for record in records where record.encryptionStrength != nil {
            try cancellation?.check()
            try validateEncryptedEntry(
                record,
                password: password,
                cancellation: cancellation
            )
        }
    }

    func streamUncompressedData(
        for record: ZipRecord,
        password: String?,
        outputLimit: UInt64,
        cancellation: ZipOperationCancellation? = nil,
        _ output: @escaping (Data) throws -> Void
    ) throws {
        var crc = CRC32()
        var restoredSize: UInt64 = 0
        let consume: (Data) throws -> Void = { data in
            try cancellation?.check()
            let byteCount = UInt64(data.count)
            guard restoredSize <= outputLimit, byteCount <= outputLimit - restoredSize else {
                throw ZipError.outputLimitExceeded
            }
            restoredSize += byteCount
            crc.update(data)
            try output(data)
        }

        let streamCompressed: ((Data) throws -> Void) throws -> Void = { consumer in
            if record.encryptionStrength != nil {
                let (layout, material) = try encryptedMaterial(for: record, password: password)
                var decryptor = try WinZipAESCTR(key: material.encryptionKey)
                try source.forEachChunk(
                    offset: layout.ciphertextOffset,
                    length: layout.ciphertextSize
                ) { encrypted in
                    try cancellation?.check()
                    try consumer(decryptor.update(encrypted))
                }
            } else {
                try source.forEachChunk(
                    offset: record.dataOffset,
                    length: record.compressedSize
                ) {
                    try cancellation?.check()
                    try consumer($0)
                }
            }
        }

        switch record.compressionMethod {
        case 0:
            try streamCompressed(consume)
        case 8:
            var decoder = try RawDeflateDecoder(outputLimit: outputLimit, output: consume)
            try streamCompressed { try decoder.update($0) }
            try decoder.finalize()
        default:
            throw ZipError.unsupportedFeature(
                "Unsupported ZIP compression method \(record.compressionMethod)"
            )
        }

        guard restoredSize == record.uncompressedSize else {
            throw ZipError.invalidArchive("Uncompressed size does not match ZIP directory")
        }
        if record.encryptionStrength == nil || record.aesVendorVersion == 1 {
            guard crc.finalized == record.crc32 else {
                throw ZipError.invalidArchive("CRC-32 validation failed")
            }
        }
    }

    private func validateEncryptedEntry(
        _ record: ZipRecord,
        password: String?,
        cancellation: ZipOperationCancellation?
    ) throws {
        let (layout, material) = try encryptedMaterial(for: record, password: password)
        let context = HMACSHA1Context(key: material.authenticationKey)
        try source.forEachChunk(
            offset: layout.ciphertextOffset,
            length: layout.ciphertextSize
        ) {
            try cancellation?.check()
            context.update($0)
        }
        let expected = Data(context.finalize().prefix(10))
        guard ConstantTime.equals(layout.authentication, expected) else {
            throw ZipError.authenticationFailed
        }
    }

    private func encryptedMaterial(
        for record: ZipRecord,
        password: String?
    ) throws -> (EncryptedLayout, WinZipAESKeyMaterial) {
        guard let strength = record.encryptionStrength, let password else {
            throw ZipError.wrongPassword
        }
        let minimumSize = UInt64(strength.saltByteCount + 2 + 10)
        guard record.compressedSize >= minimumSize else {
            throw ZipError.truncatedArchive
        }
        let salt = try source.read(offset: record.dataOffset, count: strength.saltByteCount)
        let verifierOffset = try Self.add(record.dataOffset, UInt64(strength.saltByteCount))
        let verifier = try source.read(offset: verifierOffset, count: 2)
        let authenticationOffset = try Self.add(
            record.dataOffset,
            record.compressedSize - 10
        )
        let authentication = try source.read(offset: authenticationOffset, count: 10)
        let material = try WinZipAESKeyMaterial.derive(
            password: password,
            salt: salt,
            strength: strength
        )
        guard ConstantTime.equals(verifier, material.passwordVerification) else {
            throw ZipError.wrongPassword
        }
        return (
            EncryptedLayout(
                ciphertextOffset: verifierOffset + 2,
                ciphertextSize: record.compressedSize - minimumSize,
                authentication: authentication
            ),
            material
        )
    }

    private static func parseRecords(
        _ source: any ArchiveByteSource,
        cancellation: ZipOperationCancellation?
    ) throws -> [ZipRecord] {
        let eocdOffset = try locateEndOfCentralDirectory(source)
        let directory = try parseDirectoryInfo(source, eocdOffset: eocdOffset)
        guard directory.entryCount <= 100_000 else {
            throw ZipError.tooManyEntries
        }
        guard directory.entryCount <= UInt64(Int.max),
              directory.offset <= source.size,
              directory.size <= source.size - directory.offset else {
            throw ZipError.truncatedArchive
        }

        var cursorOffset = directory.offset
        let centralEnd = try add(directory.offset, directory.size)
        var records: [ZipRecord] = []
        records.reserveCapacity(Int(directory.entryCount))

        for _ in 0..<directory.entryCount {
            try cancellation?.check()
            let fixed = try source.read(offset: cursorOffset, count: 46)
            var cursor = ByteCursor(data: fixed)
            guard try cursor.readUInt32() == 0x0201_4B50 else {
                throw ZipError.invalidArchive("Invalid central directory signature")
            }
            let versionMadeBy = try cursor.readUInt16()
            _ = try cursor.readUInt16()
            let flags = try cursor.readUInt16()
            let storedMethod = try cursor.readUInt16()
            _ = try cursor.readUInt16()
            _ = try cursor.readUInt16()
            let crc32 = try cursor.readUInt32()
            let compressed32 = try cursor.readUInt32()
            let uncompressed32 = try cursor.readUInt32()
            let nameLength = try cursor.readUInt16()
            let extraLength = try cursor.readUInt16()
            let commentLength = try cursor.readUInt16()
            let diskStart16 = try cursor.readUInt16()
            _ = try cursor.readUInt16()
            let externalAttributes = try cursor.readUInt32()
            let localOffset32 = try cursor.readUInt32()

            cursorOffset = try add(cursorOffset, 46)
            let nameData = try source.read(offset: cursorOffset, count: Int(nameLength))
            cursorOffset = try add(cursorOffset, UInt64(nameLength))
            let extra = try source.read(offset: cursorOffset, count: Int(extraLength))
            cursorOffset = try add(cursorOffset, UInt64(extraLength))
            cursorOffset = try add(cursorOffset, UInt64(commentLength))
            guard cursorOffset <= centralEnd else { throw ZipError.truncatedArchive }
            guard let path = String(data: nameData, encoding: .utf8), !path.isEmpty else {
                throw ZipError.invalidArchive("ZIP entry name is not valid UTF-8")
            }
            let sourcePlatform = versionMadeBy >> 8
            let unixMode = externalAttributes >> 16
            if sourcePlatform == 3, unixMode & 0o170000 == 0o120000 {
                throw ZipError.unsupportedFeature("Symbolic links are not extracted")
            }

            let resolved = try parseZIP64Extra(
                extra,
                compressed32: compressed32,
                uncompressed32: uncompressed32,
                localOffset32: localOffset32,
                diskStart16: diskStart16
            )
            guard resolved.diskStart == 0 else {
                throw ZipError.unsupportedFeature("Multi-disk ZIP archives are not supported")
            }
            let aes = try parseAESExtra(extra)
            let encrypted = flags & 1 == 1
            if aes == nil, encrypted {
                throw ZipError.unsupportedFeature("Traditional ZipCrypto encryption is not supported")
            }
            guard aes == nil || encrypted else {
                throw ZipError.invalidArchive("WinZip AES entry is missing its encryption flag")
            }
            let method: UInt16
            if storedMethod == 99 {
                guard let aes else {
                    throw ZipError.invalidArchive("AES ZIP entry is missing its extra field")
                }
                method = aes.actualMethod
            } else {
                guard aes == nil else {
                    throw ZipError.invalidArchive("Unexpected AES extra field")
                }
                method = storedMethod
            }

            let dataOffset = try localDataOffset(
                source,
                localHeaderOffset: resolved.localOffset,
                expectedName: nameData,
                expectedFlags: flags,
                expectedStoredMethod: storedMethod,
                expectedCRC32: crc32,
                expectedCompressedSize: resolved.compressed,
                expectedUncompressedSize: resolved.uncompressed
            )
            let payloadEnd = try add(dataOffset, resolved.compressed)
            guard payloadEnd <= directory.offset else {
                throw ZipError.truncatedArchive
            }
            records.append(ZipRecord(
                path: path,
                compressedSize: resolved.compressed,
                uncompressedSize: resolved.uncompressed,
                crc32: crc32,
                compressionMethod: method,
                isDirectory: path.hasSuffix("/"),
                encryptionStrength: aes?.strength,
                aesVendorVersion: aes?.version,
                dataOffset: dataOffset
            ))
        }
        guard cursorOffset == centralEnd else {
            throw ZipError.invalidArchive("Central directory size does not match its entries")
        }
        return records
    }

    private static func locateEndOfCentralDirectory(
        _ source: any ArchiveByteSource
    ) throws -> UInt64 {
        guard source.size >= 22 else { throw ZipError.truncatedArchive }
        let tailLength = Int(min(source.size, UInt64(22 + Int(UInt16.max))))
        let tailOffset = source.size - UInt64(tailLength)
        let tail = try source.read(offset: tailOffset, count: tailLength)
        for localOffset in stride(from: tail.count - 22, through: 0, by: -1) {
            guard tail[localOffset] == 0x50,
                  tail[localOffset + 1] == 0x4B,
                  tail[localOffset + 2] == 0x05,
                  tail[localOffset + 3] == 0x06 else { continue }
            var cursor = ByteCursor(data: tail, offset: localOffset + 20)
            let commentLength = try cursor.readUInt16()
            if localOffset + 22 + Int(commentLength) == tail.count {
                return tailOffset + UInt64(localOffset)
            }
        }
        throw ZipError.invalidArchive("End of central directory was not found")
    }

    private static func parseDirectoryInfo(
        _ source: any ArchiveByteSource,
        eocdOffset: UInt64
    ) throws -> DirectoryInfo {
        var eocd = ByteCursor(data: try source.read(offset: eocdOffset, count: 22), offset: 4)
        let disk = try eocd.readUInt16()
        let centralDisk = try eocd.readUInt16()
        let entriesOnDisk = try eocd.readUInt16()
        let totalEntries = try eocd.readUInt16()
        let centralSize = try eocd.readUInt32()
        let centralOffset = try eocd.readUInt32()
        _ = try eocd.readUInt16()
        guard disk == 0, centralDisk == 0 else {
            throw ZipError.unsupportedFeature("Multi-disk ZIP archives are not supported")
        }

        let needsZIP64 = entriesOnDisk == UInt16.max
            || totalEntries == UInt16.max
            || centralSize == UInt32.max
            || centralOffset == UInt32.max
        if !needsZIP64 {
            guard entriesOnDisk == totalEntries else {
                throw ZipError.unsupportedFeature("Multi-disk ZIP archives are not supported")
            }
            return DirectoryInfo(
                entryCount: UInt64(totalEntries),
                offset: UInt64(centralOffset),
                size: UInt64(centralSize)
            )
        }

        guard eocdOffset >= 20 else { throw ZipError.truncatedArchive }
        let locatorOffset = eocdOffset - 20
        var locator = ByteCursor(data: try source.read(offset: locatorOffset, count: 20))
        guard try locator.readUInt32() == 0x0706_4B50 else {
            throw ZipError.invalidArchive("ZIP64 locator was not found")
        }
        let recordDisk = try locator.readUInt32()
        let recordOffset = try locator.readUInt64()
        let totalDisks = try locator.readUInt32()
        guard recordDisk == 0, totalDisks == 1 else {
            throw ZipError.unsupportedFeature("Multi-disk ZIP archives are not supported")
        }
        var record = ByteCursor(data: try source.read(offset: recordOffset, count: 56))
        guard try record.readUInt32() == 0x0606_4B50 else {
            throw ZipError.invalidArchive("ZIP64 end of central directory was not found")
        }
        let recordSize = try record.readUInt64()
        guard recordSize >= 44,
              try add(recordOffset, try add(12, recordSize)) <= locatorOffset else {
            throw ZipError.truncatedArchive
        }
        _ = try record.readUInt16()
        _ = try record.readUInt16()
        let zip64Disk = try record.readUInt32()
        let zip64CentralDisk = try record.readUInt32()
        let zip64EntriesOnDisk = try record.readUInt64()
        let zip64Entries = try record.readUInt64()
        let zip64CentralSize = try record.readUInt64()
        let zip64CentralOffset = try record.readUInt64()
        guard zip64Disk == 0,
              zip64CentralDisk == 0,
              zip64EntriesOnDisk == zip64Entries else {
            throw ZipError.unsupportedFeature("Multi-disk ZIP archives are not supported")
        }
        return DirectoryInfo(
            entryCount: zip64Entries,
            offset: zip64CentralOffset,
            size: zip64CentralSize
        )
    }

    private static func localDataOffset(
        _ source: any ArchiveByteSource,
        localHeaderOffset: UInt64,
        expectedName: Data,
        expectedFlags: UInt16,
        expectedStoredMethod: UInt16,
        expectedCRC32: UInt32,
        expectedCompressedSize: UInt64,
        expectedUncompressedSize: UInt64
    ) throws -> UInt64 {
        var cursor = ByteCursor(data: try source.read(offset: localHeaderOffset, count: 30))
        guard try cursor.readUInt32() == 0x0403_4B50 else {
            throw ZipError.invalidArchive("Invalid local file header")
        }
        _ = try cursor.readUInt16()
        let flags = try cursor.readUInt16()
        let method = try cursor.readUInt16()
        try cursor.skip(4)
        let crc32 = try cursor.readUInt32()
        let compressed32 = try cursor.readUInt32()
        let uncompressed32 = try cursor.readUInt32()
        let nameLength = try cursor.readUInt16()
        let extraLength = try cursor.readUInt16()
        guard method == expectedStoredMethod,
              flags & 0x0809 == expectedFlags & 0x0809 else {
            throw ZipError.invalidArchive("Local and central ZIP headers do not match")
        }
        let nameOffset = try add(localHeaderOffset, 30)
        let localName = try source.read(offset: nameOffset, count: Int(nameLength))
        guard localName == expectedName else {
            throw ZipError.invalidArchive("Local and central ZIP entry names do not match")
        }
        let extraOffset = try add(nameOffset, UInt64(nameLength))
        let extra = try source.read(offset: extraOffset, count: Int(extraLength))
        if flags & (1 << 3) == 0 {
            let localSizes = try parseZIP64Extra(
                extra,
                compressed32: compressed32,
                uncompressed32: uncompressed32,
                localOffset32: 0,
                diskStart16: 0
            )
            guard localSizes.compressed == expectedCompressedSize,
                  localSizes.uncompressed == expectedUncompressedSize,
                  crc32 == expectedCRC32 else {
                throw ZipError.invalidArchive("Local and central ZIP headers do not match")
            }
        }
        return try add(extraOffset, UInt64(extraLength))
    }

    private static func parseZIP64Extra(
        _ extra: Data,
        compressed32: UInt32,
        uncompressed32: UInt32,
        localOffset32: UInt32,
        diskStart16: UInt16
    ) throws -> (compressed: UInt64, uncompressed: UInt64, localOffset: UInt64, diskStart: UInt32) {
        let needsUncompressed = uncompressed32 == UInt32.max
        let needsCompressed = compressed32 == UInt32.max
        let needsOffset = localOffset32 == UInt32.max
        let needsDisk = diskStart16 == UInt16.max
        if !needsUncompressed, !needsCompressed, !needsOffset, !needsDisk {
            return (
                UInt64(compressed32),
                UInt64(uncompressed32),
                UInt64(localOffset32),
                UInt32(diskStart16)
            )
        }

        var fields = ByteCursor(data: extra)
        while fields.remainingCount > 0 {
            guard fields.remainingCount >= 4 else { throw ZipError.truncatedArchive }
            let identifier = try fields.readUInt16()
            let size = try fields.readUInt16()
            let payload = try fields.read(count: Int(size))
            guard identifier == 0x0001 else { continue }
            var zip64 = ByteCursor(data: payload)
            let uncompressed = needsUncompressed ? try zip64.readUInt64() : UInt64(uncompressed32)
            let compressed = needsCompressed ? try zip64.readUInt64() : UInt64(compressed32)
            let localOffset = needsOffset ? try zip64.readUInt64() : UInt64(localOffset32)
            let disk = needsDisk ? try zip64.readUInt32() : UInt32(diskStart16)
            return (compressed, uncompressed, localOffset, disk)
        }
        throw ZipError.invalidArchive("ZIP64 extra field was not found")
    }

    private static func parseAESExtra(_ extra: Data) throws -> AESExtra? {
        var cursor = ByteCursor(data: extra)
        while cursor.remainingCount > 0 {
            guard cursor.remainingCount >= 4 else { throw ZipError.truncatedArchive }
            let identifier = try cursor.readUInt16()
            let size = try cursor.readUInt16()
            let payload = try cursor.read(count: Int(size))
            guard identifier == 0x9901 else { continue }
            guard payload.count == 7 else {
                throw ZipError.invalidArchive("Invalid WinZip AES extra field")
            }
            var aes = ByteCursor(data: payload)
            let version = try aes.readUInt16()
            let vendor = try aes.read(count: 2)
            let strengthByte = try aes.read(count: 1).first!
            let method = try aes.readUInt16()
            guard (version == 1 || version == 2),
                  vendor == Data([0x41, 0x45]),
                  let strength = WinZipAESStrength(rawValue: strengthByte) else {
                throw ZipError.invalidArchive("Unsupported WinZip AES parameters")
            }
            return AESExtra(version: version, strength: strength, actualMethod: method)
        }
        return nil
    }

    private static func add(_ lhs: UInt64, _ rhs: UInt64) throws -> UInt64 {
        guard rhs <= UInt64.max - lhs else { throw ZipError.truncatedArchive }
        return lhs + rhs
    }
}
