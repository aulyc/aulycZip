import Foundation

public enum FinderArchiveRequestError: Error, Equatable, Sendable {
    case noUsableFiles
    case invalidDestinationDirectory
    case invalidOutputFileName
}

public struct FinderArchiveRequest: Equatable, Sendable {
    public let sourceURLs: [URL]
    public let destinationURL: URL

    public var targetSummary: String {
        let paths = sourceURLs.map(\.path)
        guard paths.count > 2 else {
            return paths.joined(separator: "、")
        }
        return "\(paths[0])、\(paths[1]) 等 \(paths.count) 项"
    }

    public init(
        sourceURLs: [URL],
        destinationDirectoryURL: URL? = nil,
        outputFileName: String? = nil,
        fileManager: FileManager = .default
    ) throws {
        var seenPaths = Set<String>()
        let usableSources = sourceURLs.compactMap { source -> URL? in
            guard source.isFileURL else { return nil }
            let standardized = source.standardizedFileURL
            guard fileManager.fileExists(atPath: standardized.path),
                  seenPaths.insert(standardized.path).inserted else {
                return nil
            }
            return standardized
        }
        guard let first = usableSources.first else {
            throw FinderArchiveRequestError.noUsableFiles
        }

        self.sourceURLs = usableSources
        let parent: URL
        if let destinationDirectoryURL {
            let standardized = destinationDirectoryURL.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard destinationDirectoryURL.isFileURL,
                  fileManager.fileExists(atPath: standardized.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw FinderArchiveRequestError.invalidDestinationDirectory
            }
            parent = standardized
        } else {
            parent = first.deletingLastPathComponent()
        }
        let preferredFileName: String
        if let outputFileName {
            preferredFileName = try Self.normalizedOutputFileName(outputFileName)
        } else {
            let baseName: String
            if usableSources.count == 1 {
                let isDirectory = (try? first.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                let sourceName = isDirectory
                    ? first.lastPathComponent
                    : first.deletingPathExtension().lastPathComponent
                baseName = (sourceName.isEmpty ? "加密归档" : sourceName + " 加密")
            } else {
                baseName = "加密归档"
            }
            preferredFileName = baseName + ".zip"
        }
        destinationURL = Self.uniqueDestination(
            below: parent,
            preferredFileName: preferredFileName,
            fileManager: fileManager
        )
    }

    private static func normalizedOutputFileName(_ rawName: String) throws -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalidCharacters = CharacterSet(charactersIn: "/\\:\0")
        guard !name.isEmpty,
              name != ".",
              name != "..",
              name.rangeOfCharacter(from: invalidCharacters) == nil else {
            throw FinderArchiveRequestError.invalidOutputFileName
        }
        let fileName = name.lowercased().hasSuffix(".zip") ? name : name + ".zip"
        guard fileName.utf8.count <= 255 else {
            throw FinderArchiveRequestError.invalidOutputFileName
        }
        return fileName
    }

    private static func uniqueDestination(
        below parent: URL,
        preferredFileName: String,
        fileManager: FileManager
    ) -> URL {
        var suffix = 1
        let preferredURL = parent.appendingPathComponent(preferredFileName)
        let pathExtension = preferredURL.pathExtension
        let baseName = preferredURL.deletingPathExtension().lastPathComponent
        var candidate = preferredURL
        while fileManager.fileExists(atPath: candidate.path) {
            suffix += 1
            let suffixedName = pathExtension.isEmpty
                ? "\(baseName) \(suffix)"
                : "\(baseName) \(suffix).\(pathExtension)"
            candidate = parent.appendingPathComponent(suffixedName)
        }
        return candidate
    }
}
