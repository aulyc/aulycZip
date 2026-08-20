import Foundation
import ZipCore

public enum EncryptedArchiveCreationError: Error, Equatable, Sendable {
    case destinationExists
}

public enum EncryptedArchiveCreator {
    public static func create(
        request: EncryptedArchiveRequest,
        password: String,
        cancellation: ZipOperationCancellation? = nil,
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
            encryption: .winZipAES256(password: password),
            cancellation: cancellation
        )

        try cancellation?.throwIfCancelled()
        guard !fileManager.fileExists(atPath: request.destinationURL.path) else {
            throw EncryptedArchiveCreationError.destinationExists
        }

        do {
            try fileManager.moveItem(at: temporaryURL, to: request.destinationURL)
        } catch {
            if fileManager.fileExists(atPath: request.destinationURL.path) {
                throw EncryptedArchiveCreationError.destinationExists
            }
            throw error
        }
        return request.destinationURL
    }
}
