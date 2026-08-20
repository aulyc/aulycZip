import Foundation

public enum ZipExtractionDestinationPolicy: Sendable {
    case createNewDirectory
    case mergeIntoExistingDirectory
}

public enum ZipArchive {
    public static func create(
        at destination: URL,
        contentsOf sourceURLs: [URL],
        encryption: ZipCreationEncryption,
        destinationPolicy: ZipCreationDestinationPolicy = .refuseExisting,
        cancellation: ZipOperationCancellation? = nil
    ) throws {
        try ZipArchiveWriter.create(
            at: destination,
            contentsOf: sourceURLs,
            encryption: encryption,
            destinationPolicy: destinationPolicy,
            cancellation: cancellation
        )
    }

    public static func list(
        _ archive: URL,
        cancellation: ZipOperationCancellation? = nil
    ) throws -> [ZipEntry] {
        try ZipArchiveReader(url: archive, cancellation: cancellation)
            .records
            .filter { !isMacOSMetadataPath($0.path) }
            .map(\.publicEntry)
    }

    public static func extract(
        _ archive: URL,
        to destination: URL,
        password: String? = nil,
        destinationPolicy: ZipExtractionDestinationPolicy = .createNewDirectory,
        limits: ZipExtractionLimits = .standard,
        cancellation: ZipOperationCancellation? = nil
    ) throws {
        try cancellation?.check()
        let fileManager = FileManager.default
        let stagingParent: URL
        switch destinationPolicy {
        case .createNewDirectory:
            if fileManager.fileExists(atPath: destination.path) {
                let values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey])
                if values.isSymbolicLink == true {
                    throw ZipError.unsafeEntryPath(destination.path)
                }
                throw ZipError.destinationAlreadyExists(destination.path)
            }
            stagingParent = destination.deletingLastPathComponent()
        case .mergeIntoExistingDirectory:
            var isDirectory = ObjCBool(false)
            let exists = fileManager.fileExists(
                atPath: destination.path,
                isDirectory: &isDirectory
            )
            guard exists, isDirectory.boolValue else {
                throw ZipError.unsafeEntryPath(destination.path)
            }
            let values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw ZipError.unsafeEntryPath(destination.path)
            }
            stagingParent = destination
        }

        let reader = try ZipArchiveReader(url: archive, cancellation: cancellation)
        let records = reader.records.filter { !isMacOSMetadataPath($0.path) }
        guard !records.isEmpty else {
            throw ZipError.invalidArchive("ZIP contains no extractable files")
        }
        guard limits.maximumEntryCount >= 0,
              reader.records.count <= limits.maximumEntryCount else {
            throw ZipError.tooManyEntries
        }
        var declaredTotal: UInt64 = 0
        for record in records {
            guard record.uncompressedSize <= limits.maximumEntryUncompressedSize,
                  record.uncompressedSize <= limits.maximumTotalUncompressedSize - min(
                    declaredTotal,
                    limits.maximumTotalUncompressedSize
                  ) else {
                throw ZipError.outputLimitExceeded
            }
            declaredTotal += record.uncompressedSize
            if record.isDirectory,
               record.compressedSize != 0 || record.uncompressedSize != 0 {
                throw ZipError.invalidArchive("Directory ZIP entry contains file data")
            }
        }

        let parentValues = try? stagingParent.resourceValues(
            forKeys: [.volumeSupportsCaseSensitiveNamesKey]
        )
        let caseSensitive = parentValues?.volumeSupportsCaseSensitiveNames ?? false
        try validateEntryPaths(
            reader.records,
            caseSensitive: caseSensitive,
            maximumPathUTF8ByteCount: limits.maximumPathUTF8ByteCount
        )
        try validateAvailableSpace(
            below: stagingParent,
            declaredOutput: declaredTotal,
            reserve: limits.minimumFreeSpaceReserve
        )

        // Authenticate every encrypted entry before creating a staging directory or plaintext file.
        try reader.validateEncryptedEntries(
            records,
            password: password,
            cancellation: cancellation
        )

        try fileManager.createDirectory(at: stagingParent, withIntermediateDirectories: true)
        let staging = stagingParent.appendingPathComponent(
            ".aulycZip-extract-\(UUID().uuidString)",
            isDirectory: true
        )
        try ArchiveFileIO.createPrivateDirectory(at: staging)
        var committed = false
        defer {
            if !committed { try? fileManager.removeItem(at: staging) }
        }

        var actualTotal: UInt64 = 0
        for record in records {
            try cancellation?.check()
            let output = try SafeExtractionPath.resolve(record.path, below: staging)
            if record.isDirectory {
                try createDirectory(at: output, below: staging)
                continue
            }
            try createParents(for: output, below: staging)
            guard fileManager.createFile(
                atPath: output.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw ZipError.invalidArchive("Unable to create extracted file")
            }
            let handle = try FileHandle(forWritingTo: output)
            var isOpen = true
            defer { if isOpen { try? handle.close() } }
            try reader.streamUncompressedData(
                for: record,
                password: password,
                outputLimit: min(record.uncompressedSize, limits.maximumEntryUncompressedSize),
                cancellation: cancellation
            ) { chunk in
                let byteCount = UInt64(chunk.count)
                guard actualTotal <= limits.maximumTotalUncompressedSize,
                      byteCount <= limits.maximumTotalUncompressedSize - actualTotal else {
                    throw ZipError.outputLimitExceeded
                }
                actualTotal += byteCount
                try handle.write(contentsOf: chunk)
            }
            try handle.synchronize()
            try handle.close()
            isOpen = false
        }

        try cancellation?.check()
        switch destinationPolicy {
        case .createNewDirectory:
            guard !fileManager.fileExists(atPath: destination.path) else {
                throw ZipError.destinationAlreadyExists(destination.path)
            }
            try fileManager.moveItem(at: staging, to: destination)
            committed = true
        case .mergeIntoExistingDirectory:
            try moveStagingContents(
                from: staging,
                into: destination,
                caseSensitive: caseSensitive,
                cancellation: cancellation
            )
            committed = true
            try? fileManager.removeItem(at: staging)
        }
    }

    private static func isMacOSMetadataPath(_ path: String) -> Bool {
        let components = path
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
        guard let first = components.first, let last = components.last else {
            return false
        }
        if first == "__MACOSX" { return true }
        if last == ".DS_Store" { return true }
        return last.hasPrefix("._")
    }

    private static func moveStagingContents(
        from staging: URL,
        into destination: URL,
        caseSensitive: Bool,
        cancellation: ZipOperationCancellation?
    ) throws {
        let fileManager = FileManager.default
        let stagedItems = try fileManager.contentsOfDirectory(
            at: staging,
            includingPropertiesForKeys: nil
        )
        let existingNames = Set(
            try fileManager.contentsOfDirectory(atPath: destination.path).map {
                normalizedFileName($0, caseSensitive: caseSensitive)
            }
        )
        for item in stagedItems {
            let normalized = normalizedFileName(
                item.lastPathComponent,
                caseSensitive: caseSensitive
            )
            guard !existingNames.contains(normalized) else {
                throw ZipError.destinationEntryAlreadyExists(
                    destination.appendingPathComponent(item.lastPathComponent).path
                )
            }
        }

        var movedItems: [(source: URL, destination: URL)] = []
        do {
            for source in stagedItems {
                try cancellation?.check()
                let target = destination.appendingPathComponent(
                    source.lastPathComponent,
                    isDirectory: false
                )
                guard !fileManager.fileExists(atPath: target.path) else {
                    throw ZipError.destinationEntryAlreadyExists(target.path)
                }
                try fileManager.moveItem(at: source, to: target)
                movedItems.append((source, target))
            }
        } catch {
            for item in movedItems.reversed() {
                try? fileManager.moveItem(at: item.destination, to: item.source)
            }
            throw error
        }
    }

    private static func normalizedFileName(_ name: String, caseSensitive: Bool) -> String {
        let normalized = name.precomposedStringWithCanonicalMapping
        guard !caseSensitive else { return normalized }
        return normalized.folding(
            options: [.caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private static func validateEntryPaths(
        _ records: [ZipRecord],
        caseSensitive: Bool,
        maximumPathUTF8ByteCount: Int
    ) throws {
        guard maximumPathUTF8ByteCount > 0 else {
            throw ZipError.outputLimitExceeded
        }
        var paths: [String: ZipRecord] = [:]
        for record in records {
            _ = try SafeExtractionPath.resolve(record.path, below: URL(fileURLWithPath: "/safe-root"))
            var normalized = record.path.replacingOccurrences(of: "\\", with: "/")
            guard normalized.utf8.count <= maximumPathUTF8ByteCount else {
                throw ZipError.unsafeEntryPath(record.path)
            }
            if normalized.hasSuffix("/") { normalized.removeLast() }
            guard normalized.split(separator: "/").allSatisfy({ $0.utf8.count <= 255 }) else {
                throw ZipError.unsafeEntryPath(record.path)
            }
            normalized = normalized.precomposedStringWithCanonicalMapping
            if !caseSensitive {
                normalized = normalized.folding(
                    options: [.caseInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                )
            }
            if paths[normalized] != nil {
                throw ZipError.duplicateEntry(record.path)
            }
            paths[normalized] = record
        }
        let files = paths.filter { !$0.value.isDirectory }
        for (filePath, _) in files {
            if paths.keys.contains(where: { $0.hasPrefix(filePath + "/") }) {
                throw ZipError.duplicateEntry(filePath)
            }
        }
    }

    private static func validateAvailableSpace(
        below parent: URL,
        declaredOutput: UInt64,
        reserve: UInt64
    ) throws {
        guard declaredOutput <= UInt64.max - reserve else {
            throw ZipError.outputLimitExceeded
        }
        var existing = parent.standardizedFileURL
        while !FileManager.default.fileExists(atPath: existing.path) {
            let next = existing.deletingLastPathComponent()
            guard next.path != existing.path else { return }
            existing = next
        }
        let values = try existing.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        guard let capacity = values.volumeAvailableCapacityForImportantUsage,
              capacity >= 0 else { return }
        guard declaredOutput + reserve <= UInt64(capacity) else {
            throw ZipError.outputLimitExceeded
        }
    }

    static func createDirectory(at directory: URL, below root: URL) throws {
        try createParents(for: directory, below: root)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            let values = try directory.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true, isDirectory.boolValue else {
                throw ZipError.unsafeEntryPath(directory.path)
            }
        } else {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
        }
    }

    static func createParents(for output: URL, below root: URL) throws {
        let root = root.standardizedFileURL
        let parent = output.deletingLastPathComponent()
        let relative = parent.path
            .dropFirst(root.path.count)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var current = root
        for component in relative.split(separator: "/") {
            current.appendPathComponent(String(component), isDirectory: true)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: current.path, isDirectory: &isDirectory) {
                let values = try current.resourceValues(forKeys: [.isSymbolicLinkKey])
                guard values.isSymbolicLink != true, isDirectory.boolValue else {
                    throw ZipError.unsafeEntryPath(output.path)
                }
            } else {
                try FileManager.default.createDirectory(
                    at: current,
                    withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o700]
                )
            }
        }
    }
}
