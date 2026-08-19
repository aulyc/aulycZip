import Foundation

struct ZipArchiveWriterOptions {
    var forceZIP64 = false
}

struct ZipArchiveWriter {
    struct ZIP64Requirements {
        let sizeFields: Bool
        let offsetField: Bool

        var usesZIP64: Bool { sizeFields || offsetField }
    }

    private struct InputEntry {
        let url: URL
        let path: String
        let isDirectory: Bool
        let modifiedAt: Date
    }

    private struct PayloadInfo {
        let compressedSize: UInt64
        let uncompressedSize: UInt64
        let crc32: UInt32
        let extra: Data
        let method: UInt16
        let flags: UInt16
        let headerCRC: UInt32
        let baseVersionNeeded: UInt16
    }

    static func create(
        at destination: URL,
        contentsOf sourceURLs: [URL],
        encryption: ZipCreationEncryption,
        destinationPolicy: ZipCreationDestinationPolicy = .refuseExisting,
        options: ZipArchiveWriterOptions = ZipArchiveWriterOptions(),
        cancellation: ZipOperationCancellation? = nil
    ) throws {
        try cancellation?.check()
        guard !sourceURLs.isEmpty else {
            throw ZipError.invalidArchive("Select at least one file or folder")
        }
        let inputs = try collectInputs(from: sourceURLs)
        guard inputs.count <= 100_000 else { throw ZipError.tooManyEntries }
        let destinationIdentity = destination.standardizedFileURL.resolvingSymlinksInPath().path
        guard !inputs.contains(where: {
            $0.url.standardizedFileURL.resolvingSymlinksInPath().path == destinationIdentity
        }) else {
            throw ZipError.destinationMatchesSource
        }

        let fileManager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            switch destinationPolicy {
            case .refuseExisting:
                throw ZipError.destinationAlreadyExists(destination.path)
            case .replaceExisting:
                try validateReplacementTarget(destination)
            }
        }

        let work = parent.appendingPathComponent(
            ".aulycZip-create-\(UUID().uuidString)",
            isDirectory: true
        )
        try ArchiveFileIO.createPrivateDirectory(at: work)
        defer { try? fileManager.removeItem(at: work) }
        let archiveURL = work.appendingPathComponent("archive.tmp")
        let centralURL = work.appendingPathComponent("central.tmp")
        let archive = try ArchiveFileIO.createArchiveOutputFile(at: archiveURL)
        let central = try ArchiveFileIO.createPrivateFile(at: centralURL)
        var archiveIsOpen = true
        var centralIsOpen = true
        defer {
            if archiveIsOpen { try? archive.close() }
            if centralIsOpen { try? central.close() }
        }

        var usesZIP64 = options.forceZIP64
        for (index, input) in inputs.enumerated() {
            try cancellation?.check()
            guard let pathData = input.path.data(using: .utf8),
                  pathData.count <= Int(UInt16.max) else {
                throw ZipError.invalidArchive("ZIP entry name is too long")
            }
            let payloadURL = work.appendingPathComponent("payload-\(index).tmp")
            let payload = try makePayload(
                for: input,
                at: payloadURL,
                encryption: encryption,
                cancellation: cancellation
            )
            defer { try? fileManager.removeItem(at: payloadURL) }

            let localOffset = try archive.offset()
            let requirements = zip64Requirements(
                compressedSize: payload.compressedSize,
                uncompressedSize: payload.uncompressedSize,
                localHeaderOffset: localOffset,
                force: options.forceZIP64
            )
            let sizeNeedsZIP64 = requirements.sizeFields
            let offsetNeedsZIP64 = requirements.offsetField
            usesZIP64 = usesZIP64 || requirements.usesZIP64
            let localZIP64 = sizeNeedsZIP64
                ? zip64Extra(values: [payload.uncompressedSize, payload.compressedSize])
                : Data()
            let localExtra = localZIP64 + payload.extra
            guard localExtra.count <= Int(UInt16.max) else {
                throw ZipError.invalidArchive("ZIP entry metadata is too large")
            }
            let versionNeeded = max(
                payload.baseVersionNeeded,
                sizeNeedsZIP64 || offsetNeedsZIP64 ? 45 : 20
            )
            let (dosTime, dosDate) = dosDateTime(input.modifiedAt)

            var localHeader = Data()
            localHeader.appendLittleEndian(UInt32(0x0403_4B50))
            localHeader.appendLittleEndian(versionNeeded)
            localHeader.appendLittleEndian(payload.flags)
            localHeader.appendLittleEndian(payload.method)
            localHeader.appendLittleEndian(dosTime)
            localHeader.appendLittleEndian(dosDate)
            localHeader.appendLittleEndian(payload.headerCRC)
            localHeader.appendLittleEndian(
                sizeNeedsZIP64 ? UInt32.max : UInt32(payload.compressedSize)
            )
            localHeader.appendLittleEndian(
                sizeNeedsZIP64 ? UInt32.max : UInt32(payload.uncompressedSize)
            )
            localHeader.appendLittleEndian(UInt16(pathData.count))
            localHeader.appendLittleEndian(UInt16(localExtra.count))
            localHeader.append(pathData)
            localHeader.append(localExtra)
            try archive.write(contentsOf: localHeader)
            try ArchiveFileIO.copy(
                from: payloadURL,
                to: archive,
                cancellation: cancellation
            )

            var zip64Values: [UInt64] = []
            if sizeNeedsZIP64 {
                zip64Values.append(payload.uncompressedSize)
                zip64Values.append(payload.compressedSize)
            }
            if offsetNeedsZIP64 { zip64Values.append(localOffset) }
            let centralExtra = (zip64Values.isEmpty ? Data() : zip64Extra(values: zip64Values))
                + payload.extra
            guard centralExtra.count <= Int(UInt16.max) else {
                throw ZipError.invalidArchive("ZIP entry metadata is too large")
            }
            var centralHeader = Data()
            centralHeader.appendLittleEndian(UInt32(0x0201_4B50))
            centralHeader.appendLittleEndian(UInt16(0x033F))
            centralHeader.appendLittleEndian(versionNeeded)
            centralHeader.appendLittleEndian(payload.flags)
            centralHeader.appendLittleEndian(payload.method)
            centralHeader.appendLittleEndian(dosTime)
            centralHeader.appendLittleEndian(dosDate)
            centralHeader.appendLittleEndian(payload.headerCRC)
            centralHeader.appendLittleEndian(
                sizeNeedsZIP64 ? UInt32.max : UInt32(payload.compressedSize)
            )
            centralHeader.appendLittleEndian(
                sizeNeedsZIP64 ? UInt32.max : UInt32(payload.uncompressedSize)
            )
            centralHeader.appendLittleEndian(UInt16(pathData.count))
            centralHeader.appendLittleEndian(UInt16(centralExtra.count))
            centralHeader.appendLittleEndian(UInt16(0))
            centralHeader.appendLittleEndian(UInt16(0))
            centralHeader.appendLittleEndian(UInt16(0))
            centralHeader.appendLittleEndian(
                input.isDirectory
                    ? UInt32(0o040755 << 16) | 0x10
                    : UInt32(0o100644 << 16)
            )
            centralHeader.appendLittleEndian(
                offsetNeedsZIP64 ? UInt32.max : UInt32(localOffset)
            )
            centralHeader.append(pathData)
            centralHeader.append(centralExtra)
            try central.write(contentsOf: centralHeader)
        }

        let centralSize = try central.offset()
        try central.synchronize()
        try central.close()
        centralIsOpen = false
        let centralOffset = try archive.offset()
        try ArchiveFileIO.copy(
            from: centralURL,
            to: archive,
            cancellation: cancellation
        )
        usesZIP64 = usesZIP64
            || inputs.count >= Int(UInt16.max)
            || centralSize >= UInt64(UInt32.max)
            || centralOffset >= UInt64(UInt32.max)

        if usesZIP64 {
            let zip64EOCDOffset = try archive.offset()
            var zip64End = Data()
            zip64End.appendLittleEndian(UInt32(0x0606_4B50))
            zip64End.appendLittleEndian(UInt64(44))
            zip64End.appendLittleEndian(UInt16(45))
            zip64End.appendLittleEndian(UInt16(45))
            zip64End.appendLittleEndian(UInt32(0))
            zip64End.appendLittleEndian(UInt32(0))
            zip64End.appendLittleEndian(UInt64(inputs.count))
            zip64End.appendLittleEndian(UInt64(inputs.count))
            zip64End.appendLittleEndian(centralSize)
            zip64End.appendLittleEndian(centralOffset)
            zip64End.appendLittleEndian(UInt32(0x0706_4B50))
            zip64End.appendLittleEndian(UInt32(0))
            zip64End.appendLittleEndian(zip64EOCDOffset)
            zip64End.appendLittleEndian(UInt32(1))
            zip64End.appendLittleEndian(UInt32(0x0605_4B50))
            zip64End.appendLittleEndian(UInt16(0))
            zip64End.appendLittleEndian(UInt16(0))
            zip64End.appendLittleEndian(UInt16.max)
            zip64End.appendLittleEndian(UInt16.max)
            zip64End.appendLittleEndian(UInt32.max)
            zip64End.appendLittleEndian(UInt32.max)
            zip64End.appendLittleEndian(UInt16(0))
            try archive.write(contentsOf: zip64End)
        } else {
            var end = Data()
            end.appendLittleEndian(UInt32(0x0605_4B50))
            end.appendLittleEndian(UInt16(0))
            end.appendLittleEndian(UInt16(0))
            end.appendLittleEndian(UInt16(inputs.count))
            end.appendLittleEndian(UInt16(inputs.count))
            end.appendLittleEndian(UInt32(centralSize))
            end.appendLittleEndian(UInt32(centralOffset))
            end.appendLittleEndian(UInt16(0))
            try archive.write(contentsOf: end)
        }
        try archive.synchronize()
        try archive.close()
        archiveIsOpen = false

        try cancellation?.check()
        if fileManager.fileExists(atPath: destination.path) {
            switch destinationPolicy {
            case .refuseExisting:
                throw ZipError.destinationAlreadyExists(destination.path)
            case .replaceExisting:
                try validateReplacementTarget(destination)
                _ = try fileManager.replaceItemAt(
                    destination,
                    withItemAt: archiveURL,
                    backupItemName: nil,
                    options: [.usingNewMetadataOnly]
                )
            }
        } else {
            try fileManager.moveItem(at: archiveURL, to: destination)
        }
    }

    private static func validateReplacementTarget(_ destination: URL) throws {
        let values = try destination.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw ZipError.destinationAlreadyExists(destination.path)
        }
    }

    private static func makePayload(
        for input: InputEntry,
        at payloadURL: URL,
        encryption: ZipCreationEncryption,
        cancellation: ZipOperationCancellation?
    ) throws -> PayloadInfo {
        let handle = try ArchiveFileIO.createPrivateFile(at: payloadURL)
        var isOpen = true
        defer { if isOpen { try? handle.close() } }
        guard !input.isDirectory else {
            try handle.close()
            isOpen = false
            return PayloadInfo(
                compressedSize: 0,
                uncompressedSize: 0,
                crc32: 0,
                extra: Data(),
                method: 0,
                flags: 1 << 11,
                headerCRC: 0,
                baseVersionNeeded: 20
            )
        }

        let actualMethod: UInt16 = 8
        var encryptor: WinZipAESCTR?
        var hmac: HMACSHA1Context?
        let extra: Data
        let method: UInt16
        let flags: UInt16
        let baseVersion: UInt16
        switch encryption {
        case .none:
            extra = Data()
            method = actualMethod
            flags = 1 << 11
            baseVersion = 20
        case .winZipAES256(let password):
            let strength = WinZipAESStrength.aes256
            let salt = try SecureRandom.bytes(count: strength.saltByteCount)
            let material = try WinZipAESKeyMaterial.derive(
                password: password,
                salt: salt,
                strength: strength
            )
            try handle.write(contentsOf: salt)
            try handle.write(contentsOf: material.passwordVerification)
            encryptor = try WinZipAESCTR(key: material.encryptionKey)
            hmac = HMACSHA1Context(key: material.authenticationKey)
            extra = aesExtra(strength: strength, actualMethod: actualMethod)
            method = 99
            flags = (1 << 11) | 1
            baseVersion = 51
        }

        var crc = CRC32()
        var inputSize: UInt64 = 0
        var encoder = try RawDeflateEncoder { compressed in
            try cancellation?.check()
            if var current = encryptor {
                let encrypted = try current.update(compressed)
                encryptor = current
                hmac?.update(encrypted)
                try handle.write(contentsOf: encrypted)
            } else {
                try handle.write(contentsOf: compressed)
            }
        }
        try ArchiveFileIO.stream(from: input.url) { chunk in
            try cancellation?.check()
            let byteCount = UInt64(chunk.count)
            guard byteCount <= UInt64.max - inputSize else {
                throw ZipError.outputLimitExceeded
            }
            inputSize += byteCount
            crc.update(chunk)
            try encoder.update(chunk)
        }
        try encoder.finalize()
        if let hmac {
            try handle.write(contentsOf: Data(hmac.finalize().prefix(10)))
        }
        let compressedSize = try handle.offset()
        try handle.synchronize()
        try handle.close()
        isOpen = false
        return PayloadInfo(
            compressedSize: compressedSize,
            uncompressedSize: inputSize,
            crc32: crc.finalized,
            extra: extra,
            method: method,
            flags: flags,
            headerCRC: encryption.isEncrypted ? 0 : crc.finalized,
            baseVersionNeeded: baseVersion
        )
    }

    private static func collectInputs(from sourceURLs: [URL]) throws -> [InputEntry] {
        var result: [InputEntry] = []
        var paths = Set<String>()
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .contentModificationDateKey,
        ]
        for source in sourceURLs {
            let selected = source.standardizedFileURL
            let selectedValues = try selected.resourceValues(forKeys: keys)
            guard selectedValues.isSymbolicLink != true else {
                throw ZipError.unsupportedFeature("Symbolic links are not archived")
            }
            let standardized = selected.resolvingSymlinksInPath()
            let rootName = standardized.lastPathComponent
            let rootValues = try standardized.resourceValues(forKeys: keys)
            try appendInput(
                url: standardized,
                path: rootValues.isDirectory == true ? rootName + "/" : rootName,
                values: rootValues,
                paths: &paths,
                result: &result
            )
            if rootValues.isDirectory == true {
                try appendDescendants(
                    below: standardized,
                    relativePrefix: "",
                    rootName: rootName,
                    keys: keys,
                    paths: &paths,
                    result: &result
                )
            }
        }
        return result
    }

    private static func appendDescendants(
        below directory: URL,
        relativePrefix: String,
        rootName: String,
        keys: Set<URLResourceKey>,
        paths: inout Set<String>,
        result: inout [InputEntry]
    ) throws {
        let children = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: []
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        for child in children {
            let values = try child.resourceValues(forKeys: keys)
            let relative = relativePrefix.isEmpty
                ? child.lastPathComponent
                : relativePrefix + "/" + child.lastPathComponent
            try appendInput(
                url: child,
                path: rootName + "/" + relative + (values.isDirectory == true ? "/" : ""),
                values: values,
                paths: &paths,
                result: &result
            )
            if values.isDirectory == true {
                try appendDescendants(
                    below: child,
                    relativePrefix: relative,
                    rootName: rootName,
                    keys: keys,
                    paths: &paths,
                    result: &result
                )
            }
        }
    }

    private static func appendInput(
        url: URL,
        path: String,
        values: URLResourceValues,
        paths: inout Set<String>,
        result: inout [InputEntry]
    ) throws {
        guard values.isSymbolicLink != true else {
            throw ZipError.unsupportedFeature("Symbolic links are not archived")
        }
        guard values.isDirectory == true || values.isRegularFile == true else {
            throw ZipError.unsupportedFeature("Only regular files and folders are supported")
        }
        guard paths.insert(path).inserted else { throw ZipError.duplicateEntry(path) }
        result.append(InputEntry(
            url: url,
            path: path,
            isDirectory: values.isDirectory == true,
            modifiedAt: values.contentModificationDate ?? Date()
        ))
    }

    private static func zip64Extra(values: [UInt64]) -> Data {
        var extra = Data()
        extra.appendLittleEndian(UInt16(0x0001))
        extra.appendLittleEndian(UInt16(values.count * MemoryLayout<UInt64>.size))
        for value in values { extra.appendLittleEndian(value) }
        return extra
    }

    static func zip64Requirements(
        compressedSize: UInt64,
        uncompressedSize: UInt64,
        localHeaderOffset: UInt64,
        force: Bool
    ) -> ZIP64Requirements {
        ZIP64Requirements(
            sizeFields: force
                || compressedSize >= UInt64(UInt32.max)
                || uncompressedSize >= UInt64(UInt32.max),
            offsetField: force || localHeaderOffset >= UInt64(UInt32.max)
        )
    }

    private static func aesExtra(strength: WinZipAESStrength, actualMethod: UInt16) -> Data {
        var extra = Data()
        extra.appendLittleEndian(UInt16(0x9901))
        extra.appendLittleEndian(UInt16(7))
        extra.appendLittleEndian(UInt16(2))
        extra.append(contentsOf: [0x41, 0x45])
        extra.append(strength.rawValue)
        extra.appendLittleEndian(actualMethod)
        return extra
    }

    private static func dosDateTime(_ date: Date) -> (time: UInt16, date: UInt16) {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: TimeZone.current, from: date)
        let year = min(max(components.year ?? 1980, 1980), 2107)
        let month = min(max(components.month ?? 1, 1), 12)
        let day = min(max(components.day ?? 1, 1), 31)
        let hour = min(max(components.hour ?? 0, 0), 23)
        let minute = min(max(components.minute ?? 0, 0), 59)
        let second = min(max(components.second ?? 0, 0), 59)
        return (
            UInt16(hour << 11 | minute << 5 | second / 2),
            UInt16((year - 1980) << 9 | month << 5 | day)
        )
    }
}

private extension ZipCreationEncryption {
    var isEncrypted: Bool {
        if case .winZipAES256 = self { return true }
        return false
    }
}
