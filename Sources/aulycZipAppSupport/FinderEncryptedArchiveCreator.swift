import Foundation
import ZipCore

public enum FinderEncryptedArchiveCreationError: Error, Equatable, Sendable {
    case destinationExists
}

public enum FinderEncryptedArchiveCreator {
    public static func create(
        request: FinderArchiveRequest,
        password: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        let parent = request.destinationURL.deletingLastPathComponent()
        let temporaryURL = parent.appendingPathComponent(
            ".aulycZip-\(UUID().uuidString).tmp"
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }

        try ZipArchive.create(
            at: temporaryURL,
            contentsOf: request.sourceURLs,
            encryption: .winZipAES256(password: password)
        )

        guard !fileManager.fileExists(atPath: request.destinationURL.path) else {
            throw FinderEncryptedArchiveCreationError.destinationExists
        }

        do {
            try fileManager.moveItem(at: temporaryURL, to: request.destinationURL)
        } catch {
            if fileManager.fileExists(atPath: request.destinationURL.path) {
                throw FinderEncryptedArchiveCreationError.destinationExists
            }
            throw error
        }
        return request.destinationURL
    }
}
