import Foundation

public enum ArchiveExtractionDestination {
    public static func resolve(
        archiveURL: URL,
        selectedParent: URL,
        createsIndependentFolder: Bool,
        fileManager: FileManager = .default
    ) -> URL {
        guard createsIndependentFolder else {
            return archiveURL.deletingLastPathComponent()
        }
        return unique(
            below: selectedParent,
            preferredName: archiveURL.deletingPathExtension().lastPathComponent,
            fileManager: fileManager
        )
    }

    public static func unique(
        below parent: URL,
        preferredName: String,
        fileManager: FileManager = .default
    ) -> URL {
        let baseName = preferredName.isEmpty ? "解压内容" : preferredName
        var candidate = parent.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(baseName) \(suffix)", isDirectory: true)
            suffix += 1
        }
        return candidate
    }
}
