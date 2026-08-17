import Foundation

public enum ZipArchive {
    public static func create(
        at destination: URL,
        contentsOf sourceURLs: [URL],
        encryption: ZipCreationEncryption
    ) throws {
        try ZipArchiveWriter.create(
            at: destination,
            contentsOf: sourceURLs,
            encryption: encryption
        )
    }

    public static func list(_ archive: URL) throws -> [ZipEntry] {
        try ZipArchiveReader(data: Data(contentsOf: archive, options: [.mappedIfSafe]))
            .records
            .map(\.publicEntry)
    }

    public static func extract(
        _ archive: URL,
        to destination: URL,
        password: String? = nil
    ) throws {
        let reader = try ZipArchiveReader(data: Data(contentsOf: archive, options: [.mappedIfSafe]))
        guard reader.records.count <= 100_000 else {
            throw ZipError.tooManyEntries
        }
        let totalSize = reader.records.reduce(UInt64(0)) { partial, record in
            partial + UInt64(record.uncompressedSize)
        }
        guard totalSize <= 20 * 1024 * 1024 * 1024 else {
            throw ZipError.outputLimitExceeded
        }

        try reader.validateEncryptedEntries(password: password)
        try prepareDestinationRoot(destination)
        for record in reader.records {
            let output = try SafeExtractionPath.resolve(record.path, below: destination)
            if record.isDirectory {
                try ensureSafeDirectory(at: output, below: destination)
                continue
            }
            try ensureSafeParent(for: output, below: destination)
            let restored = try reader.uncompressedData(for: record, password: password)
            try restored.write(to: output, options: [.atomic])
        }
    }

    private static func prepareDestinationRoot(_ destination: URL) throws {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory) {
            let values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true, isDirectory.boolValue else {
                throw ZipError.unsafeEntryPath(destination.path)
            }
        } else {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        }
    }

    private static func ensureSafeDirectory(at directory: URL, below root: URL) throws {
        try ensureSafeParent(for: directory, below: root)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            let values = try directory.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true, isDirectory.boolValue else {
                throw ZipError.unsafeEntryPath(directory.path)
            }
        } else {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        }
    }

    private static func ensureSafeParent(for output: URL, below root: URL) throws {
        let root = root.standardizedFileURL
        let parent = output.deletingLastPathComponent()
        let relative = parent.path.dropFirst(root.path.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var current = root
        if !relative.isEmpty {
            for component in relative.split(separator: "/") {
                current.appendPathComponent(String(component), isDirectory: true)
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: current.path, isDirectory: &isDirectory) {
                    let values = try current.resourceValues(forKeys: [.isSymbolicLinkKey])
                    guard values.isSymbolicLink != true, isDirectory.boolValue else {
                        throw ZipError.unsafeEntryPath(output.path)
                    }
                } else {
                    try FileManager.default.createDirectory(at: current, withIntermediateDirectories: false)
                }
            }
        }
    }
}
