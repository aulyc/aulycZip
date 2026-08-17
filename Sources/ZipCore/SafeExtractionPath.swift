import Foundation

public enum SafeExtractionPath {
    public static func resolve(_ entryPath: String, below destination: URL) throws -> URL {
        guard !entryPath.isEmpty,
              !entryPath.contains("\0"),
              !entryPath.hasPrefix("/"),
              !entryPath.hasPrefix("\\") else {
            throw ZipError.unsafeEntryPath(entryPath)
        }

        let normalized = entryPath.replacingOccurrences(of: "\\", with: "/")
        let pathWithoutDirectoryMarker = normalized.hasSuffix("/")
            ? String(normalized.dropLast())
            : normalized
        let components = pathWithoutDirectoryMarker.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              !components[0].contains(":") else {
            throw ZipError.unsafeEntryPath(entryPath)
        }

        let root = destination.standardizedFileURL
        let candidate = components.reduce(root) { partial, component in
            partial.appendingPathComponent(String(component), isDirectory: false)
        }.standardizedFileURL

        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(rootPrefix) else {
            throw ZipError.unsafeEntryPath(entryPath)
        }
        return candidate
    }
}
