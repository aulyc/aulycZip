import Foundation

struct ZipArchiveWriter {
    private struct InputEntry {
        let url: URL
        let path: String
        let isDirectory: Bool
        let modifiedAt: Date
    }

    private struct CentralEntry {
        let pathData: Data
        let extra: Data
        let versionNeeded: UInt16
        let flags: UInt16
        let method: UInt16
        let dosTime: UInt16
        let dosDate: UInt16
        let crc32: UInt32
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let externalAttributes: UInt32
        let localHeaderOffset: UInt32
    }

    static func create(
        at destination: URL,
        contentsOf sourceURLs: [URL],
        encryption: ZipCreationEncryption
    ) throws {
        guard !sourceURLs.isEmpty else {
            throw ZipError.invalidArchive("Select at least one file or folder")
        }
        let inputs = try collectInputs(from: sourceURLs)
        let destinationIdentity = destination.standardizedFileURL.resolvingSymlinksInPath().path
        guard !inputs.contains(where: {
            $0.url.standardizedFileURL.resolvingSymlinksInPath().path == destinationIdentity
        }) else {
            throw ZipError.destinationMatchesSource
        }
        guard inputs.count <= Int(UInt16.max) else {
            throw ZipError.tooManyEntries
        }

        var archive = Data()
        var centralEntries: [CentralEntry] = []
        centralEntries.reserveCapacity(inputs.count)

        for input in inputs {
            guard let pathData = input.path.data(using: .utf8), pathData.count <= Int(UInt16.max) else {
                throw ZipError.invalidArchive("ZIP entry name is too long")
            }

            let original = input.isDirectory ? Data() : try Data(contentsOf: input.url, options: [.mappedIfSafe])
            guard original.count <= Int(UInt32.max) else {
                throw ZipError.unsupportedFeature("ZIP64 writing is not available yet")
            }
            let uncompressedSize = UInt32(original.count)
            let actualMethod: UInt16 = input.isDirectory ? 0 : 8
            let compressed = input.isDirectory ? Data() : try RawDeflate.compress(original)
            let originalCRC = CRC32.checksum(original)

            let payload: Data
            let extra: Data
            let method: UInt16
            let flags: UInt16
            let headerCRC: UInt32
            let versionNeeded: UInt16
            switch encryption {
            case .none:
                payload = compressed
                extra = Data()
                method = actualMethod
                flags = 1 << 11
                headerCRC = originalCRC
                versionNeeded = 20
            case .winZipAES256(let password):
                if input.isDirectory {
                    payload = Data()
                    extra = Data()
                    method = 0
                    flags = 1 << 11
                    headerCRC = 0
                    versionNeeded = 20
                } else {
                    let strength = WinZipAESStrength.aes256
                    let salt = try SecureRandom.bytes(count: strength.saltByteCount)
                    let material = try WinZipAESKeyMaterial.derive(
                        password: password,
                        salt: salt,
                        strength: strength
                    )
                    var encryptor = try WinZipAESCTR(key: material.encryptionKey)
                    let encrypted = try encryptor.update(compressed)
                    let authentication = HMACSHA1.authenticationCode(
                        for: encrypted,
                        key: material.authenticationKey
                    ).prefix(10)
                    payload = salt + material.passwordVerification + encrypted + authentication
                    extra = aesExtra(strength: strength, actualMethod: actualMethod)
                    method = 99
                    flags = (1 << 11) | 1
                    headerCRC = 0
                    versionNeeded = 51
                }
            }

            guard payload.count <= Int(UInt32.max), archive.count <= Int(UInt32.max) else {
                throw ZipError.unsupportedFeature("ZIP64 writing is not available yet")
            }
            let compressedSize = UInt32(payload.count)
            let localHeaderOffset = UInt32(archive.count)
            let (dosTime, dosDate) = dosDateTime(input.modifiedAt)

            archive.appendLittleEndian(UInt32(0x0403_4B50))
            archive.appendLittleEndian(versionNeeded)
            archive.appendLittleEndian(flags)
            archive.appendLittleEndian(method)
            archive.appendLittleEndian(dosTime)
            archive.appendLittleEndian(dosDate)
            archive.appendLittleEndian(headerCRC)
            archive.appendLittleEndian(compressedSize)
            archive.appendLittleEndian(uncompressedSize)
            archive.appendLittleEndian(UInt16(pathData.count))
            archive.appendLittleEndian(UInt16(extra.count))
            archive.append(pathData)
            archive.append(extra)
            archive.append(payload)

            centralEntries.append(CentralEntry(
                pathData: pathData,
                extra: extra,
                versionNeeded: versionNeeded,
                flags: flags,
                method: method,
                dosTime: dosTime,
                dosDate: dosDate,
                crc32: headerCRC,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                externalAttributes: input.isDirectory ? UInt32(0o040755 << 16) | 0x10 : UInt32(0o100644 << 16),
                localHeaderOffset: localHeaderOffset
            ))
        }

        guard archive.count <= Int(UInt32.max) else {
            throw ZipError.unsupportedFeature("ZIP64 writing is not available yet")
        }
        let centralDirectoryOffset = UInt32(archive.count)
        for entry in centralEntries {
            archive.appendLittleEndian(UInt32(0x0201_4B50))
            archive.appendLittleEndian(UInt16(0x033F))
            archive.appendLittleEndian(entry.versionNeeded)
            archive.appendLittleEndian(entry.flags)
            archive.appendLittleEndian(entry.method)
            archive.appendLittleEndian(entry.dosTime)
            archive.appendLittleEndian(entry.dosDate)
            archive.appendLittleEndian(entry.crc32)
            archive.appendLittleEndian(entry.compressedSize)
            archive.appendLittleEndian(entry.uncompressedSize)
            archive.appendLittleEndian(UInt16(entry.pathData.count))
            archive.appendLittleEndian(UInt16(entry.extra.count))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(entry.externalAttributes)
            archive.appendLittleEndian(entry.localHeaderOffset)
            archive.append(entry.pathData)
            archive.append(entry.extra)
        }
        let centralDirectorySize = UInt32(archive.count) - centralDirectoryOffset

        archive.appendLittleEndian(UInt32(0x0605_4B50))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(centralEntries.count))
        archive.appendLittleEndian(UInt16(centralEntries.count))
        archive.appendLittleEndian(centralDirectorySize)
        archive.appendLittleEndian(centralDirectoryOffset)
        archive.appendLittleEndian(UInt16(0))

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try archive.write(to: destination, options: [.atomic])
    }

    private static func collectInputs(from sourceURLs: [URL]) throws -> [InputEntry] {
        var result: [InputEntry] = []
        var paths = Set<String>()
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]

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
            let directorySuffix = values.isDirectory == true ? "/" : ""
            try appendInput(
                url: child,
                path: rootName + "/" + relative + directorySuffix,
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
        guard paths.insert(path).inserted else {
            throw ZipError.duplicateEntry(path)
        }
        result.append(InputEntry(
            url: url,
            path: path,
            isDirectory: values.isDirectory == true,
            modifiedAt: values.contentModificationDate ?? Date()
        ))
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
        let dosTime = UInt16(hour << 11 | minute << 5 | second / 2)
        let dosDate = UInt16((year - 1980) << 9 | month << 5 | day)
        return (dosTime, dosDate)
    }
}
