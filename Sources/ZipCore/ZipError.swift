import Foundation

public enum ZipError: Error, Equatable, Sendable {
    case truncatedArchive
    case invalidArchive(String)
    case unsupportedFeature(String)
    case unsafeEntryPath(String)
    case wrongPassword
    case authenticationFailed
    case outputLimitExceeded
    case duplicateEntry(String)
    case destinationMatchesSource
    case destinationAlreadyExists(String)
    case tooManyEntries
    case cancelled
}
