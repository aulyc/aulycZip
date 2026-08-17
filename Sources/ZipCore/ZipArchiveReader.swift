import Foundation

struct ZipArchiveReader {
    let data: Data
    let records: [ZipRecord]

    init(data: Data) throws {
        self.data = data
        let parsed = try Self.parseRecords(data)
        var paths = Set<String>()
        for record in parsed where !paths.insert(record.path).inserted {
            throw ZipError.duplicateEntry(record.path)
        }
        records = parsed
    }

    func validateEncryptedEntries(password: String?) throws {
        for record in records where record.encryptionStrength != nil {
            _ = try encryptedCompressedData(for: record, password: password, validateOnly: true)
        }
    }

    func uncompressedData(for record: ZipRecord, password: String?) throws -> Data {
        let compressed: Data
        if record.encryptionStrength != nil {
            compressed = try encryptedCompressedData(for: record, password: password, validateOnly: false)
        } else {
            compressed = try payload(for: record)
        }

        let restored: Data
        switch record.compressionMethod {
        case 0:
            restored = compressed
        case 8:
            restored = try RawDeflate.decompress(compressed, outputLimit: Int(record.uncompressedSize))
        default:
            throw ZipError.unsupportedFeature("Unsupported ZIP compression method \(record.compressionMethod)")
        }

        guard restored.count == Int(record.uncompressedSize) else {
            throw ZipError.invalidArchive("Uncompressed size does not match ZIP directory")
        }
        if record.encryptionStrength == nil || record.aesVendorVersion == 1 {
            guard CRC32.checksum(restored) == record.crc32 else {
                throw ZipError.invalidArchive("CRC-32 validation failed")
            }
        }
        return restored
    }

    private func encryptedCompressedData(
        for record: ZipRecord,
        password: String?,
        validateOnly: Bool
    ) throws -> Data {
        guard let strength = record.encryptionStrength, let password else {
            throw ZipError.wrongPassword
        }
        let payload = try payload(for: record)
        let minimumSize = strength.saltByteCount + 2 + 10
        guard payload.count >= minimumSize else {
            throw ZipError.truncatedArchive
        }

        let salt = payload.prefix(strength.saltByteCount)
        let verifierStart = strength.saltByteCount
        let verifier = payload[verifierStart..<(verifierStart + 2)]
        let authenticationStart = payload.count - 10
        let encrypted = payload[(verifierStart + 2)..<authenticationStart]
        let authentication = payload.suffix(10)
        let material = try WinZipAESKeyMaterial.derive(
            password: password,
            salt: Data(salt),
            strength: strength
        )
        guard ConstantTime.equals(Data(verifier), material.passwordVerification) else {
            throw ZipError.wrongPassword
        }
        let expectedAuthentication = HMACSHA1.authenticationCode(
            for: Data(encrypted),
            key: material.authenticationKey
        ).prefix(10)
        guard ConstantTime.equals(Data(authentication), Data(expectedAuthentication)) else {
            throw ZipError.authenticationFailed
        }
        if validateOnly {
            return Data()
        }
        var decryptor = try WinZipAESCTR(key: material.encryptionKey)
        return try decryptor.update(encrypted)
    }

    private func payload(for record: ZipRecord) throws -> Data {
        let end = record.dataOffset + Int(record.compressedSize)
        guard record.dataOffset >= 0, end >= record.dataOffset, end <= data.count else {
            throw ZipError.truncatedArchive
        }
        return data.subdata(in: record.dataOffset..<end)
    }

    private static func parseRecords(_ data: Data) throws -> [ZipRecord] {
        let eocdOffset = try locateEndOfCentralDirectory(data)
        var eocd = ByteCursor(data: data, offset: eocdOffset + 4)
        let disk = try eocd.readUInt16()
        let centralDisk = try eocd.readUInt16()
        let entriesOnDisk = try eocd.readUInt16()
        let totalEntries = try eocd.readUInt16()
        let centralSize = try eocd.readUInt32()
        let centralOffset = try eocd.readUInt32()
        let commentLength = try eocd.readUInt16()
        guard disk == 0, centralDisk == 0, entriesOnDisk == totalEntries else {
            throw ZipError.unsupportedFeature("Multi-disk ZIP archives are not supported")
        }
        guard totalEntries != UInt16.max,
              centralSize != UInt32.max,
              centralOffset != UInt32.max else {
            throw ZipError.unsupportedFeature("ZIP64 reading is not available yet")
        }
        guard eocdOffset + 22 + Int(commentLength) == data.count,
              Int(centralOffset) + Int(centralSize) <= data.count else {
            throw ZipError.truncatedArchive
        }

        var cursor = ByteCursor(data: data, offset: Int(centralOffset))
        var records: [ZipRecord] = []
        records.reserveCapacity(Int(totalEntries))
        for _ in 0..<totalEntries {
            guard try cursor.readUInt32() == 0x0201_4B50 else {
                throw ZipError.invalidArchive("Invalid central directory signature")
            }
            _ = try cursor.readUInt16()
            _ = try cursor.readUInt16()
            let flags = try cursor.readUInt16()
            let storedMethod = try cursor.readUInt16()
            _ = try cursor.readUInt16()
            _ = try cursor.readUInt16()
            let crc32 = try cursor.readUInt32()
            let compressedSize = try cursor.readUInt32()
            let uncompressedSize = try cursor.readUInt32()
            let nameLength = try cursor.readUInt16()
            let extraLength = try cursor.readUInt16()
            let archiveCommentLength = try cursor.readUInt16()
            let diskStart = try cursor.readUInt16()
            _ = try cursor.readUInt16()
            _ = try cursor.readUInt32()
            let localOffset = try cursor.readUInt32()
            guard diskStart == 0 else {
                throw ZipError.unsupportedFeature("Multi-disk ZIP archives are not supported")
            }
            let nameData = try cursor.read(count: Int(nameLength))
            let extra = try cursor.read(count: Int(extraLength))
            try cursor.skip(Int(archiveCommentLength))
            guard let path = String(data: nameData, encoding: .utf8), !path.isEmpty else {
                throw ZipError.invalidArchive("ZIP entry name is not valid UTF-8")
            }

            let aes = try parseAESExtra(extra)
            let encryptedFlagIsSet = flags & 1 == 1
            if aes == nil, encryptedFlagIsSet {
                throw ZipError.unsupportedFeature("Traditional ZipCrypto encryption is not supported")
            }
            guard aes == nil || encryptedFlagIsSet else {
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
                data,
                localHeaderOffset: Int(localOffset),
                expectedName: nameData
            )
            records.append(ZipRecord(
                path: path,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                crc32: crc32,
                compressionMethod: method,
                flags: flags,
                isDirectory: path.hasSuffix("/"),
                encryptionStrength: aes?.strength,
                aesVendorVersion: aes?.version,
                localHeaderOffset: localOffset,
                dataOffset: dataOffset
            ))
        }
        guard cursor.offset == Int(centralOffset) + Int(centralSize) else {
            throw ZipError.invalidArchive("Central directory size does not match its entries")
        }
        return records
    }

    private static func locateEndOfCentralDirectory(_ data: Data) throws -> Int {
        guard data.count >= 22 else { throw ZipError.truncatedArchive }
        let minimum = max(0, data.count - 22 - Int(UInt16.max))
        for offset in stride(from: data.count - 22, through: minimum, by: -1) {
            if data[offset] == 0x50,
               data[offset + 1] == 0x4B,
               data[offset + 2] == 0x05,
               data[offset + 3] == 0x06 {
                return offset
            }
        }
        throw ZipError.invalidArchive("End of central directory was not found")
    }

    private static func localDataOffset(
        _ data: Data,
        localHeaderOffset: Int,
        expectedName: Data
    ) throws -> Int {
        var cursor = ByteCursor(data: data, offset: localHeaderOffset)
        guard try cursor.readUInt32() == 0x0403_4B50 else {
            throw ZipError.invalidArchive("Invalid local file header")
        }
        try cursor.skip(22)
        let nameLength = try cursor.readUInt16()
        let extraLength = try cursor.readUInt16()
        let localName = try cursor.read(count: Int(nameLength))
        guard localName == expectedName else {
            throw ZipError.invalidArchive("Local and central ZIP entry names do not match")
        }
        try cursor.skip(Int(extraLength))
        return cursor.offset
    }

    private static func parseAESExtra(
        _ extra: Data
    ) throws -> (version: UInt16, strength: WinZipAESStrength, actualMethod: UInt16)? {
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
            return (version, strength, method)
        }
        return nil
    }
}
