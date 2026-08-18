import Foundation

public final class ZipOperationCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    public func throwIfCancelled() throws {
        try check()
    }

    func check() throws {
        lock.lock()
        let isCancelled = cancelled
        lock.unlock()
        if isCancelled { throw ZipError.cancelled }
    }
}

public enum ZipCreationEncryption: Sendable {
    case none
    case winZipAES256(password: String)
}

public struct ZipExtractionLimits: Equatable, Sendable {
    public static let standard = ZipExtractionLimits(
        maximumEntryCount: 100_000,
        maximumEntryUncompressedSize: 20 * 1024 * 1024 * 1024,
        maximumTotalUncompressedSize: 20 * 1024 * 1024 * 1024,
        maximumPathUTF8ByteCount: 4_096,
        minimumFreeSpaceReserve: 512 * 1024 * 1024
    )

    public let maximumEntryCount: Int
    public let maximumEntryUncompressedSize: UInt64
    public let maximumTotalUncompressedSize: UInt64
    public let maximumPathUTF8ByteCount: Int
    public let minimumFreeSpaceReserve: UInt64

    public init(
        maximumEntryCount: Int,
        maximumEntryUncompressedSize: UInt64,
        maximumTotalUncompressedSize: UInt64,
        maximumPathUTF8ByteCount: Int = 4_096,
        minimumFreeSpaceReserve: UInt64 = 512 * 1024 * 1024
    ) {
        self.maximumEntryCount = maximumEntryCount
        self.maximumEntryUncompressedSize = maximumEntryUncompressedSize
        self.maximumTotalUncompressedSize = maximumTotalUncompressedSize
        self.maximumPathUTF8ByteCount = maximumPathUTF8ByteCount
        self.minimumFreeSpaceReserve = minimumFreeSpaceReserve
    }
}

public enum ZipEntryEncryption: String, Equatable, Sendable {
    case none
    case winZipAES128
    case winZipAES192
    case winZipAES256
}

public struct ZipEntry: Equatable, Sendable {
    public let path: String
    public let compressedSize: UInt64
    public let uncompressedSize: UInt64
    public let isDirectory: Bool
    public let encryption: ZipEntryEncryption

    public var isEncrypted: Bool {
        encryption != .none
    }
}

struct ZipRecord: Sendable {
    let path: String
    let compressedSize: UInt64
    let uncompressedSize: UInt64
    let crc32: UInt32
    let compressionMethod: UInt16
    let isDirectory: Bool
    let encryptionStrength: WinZipAESStrength?
    let aesVendorVersion: UInt16?
    let dataOffset: UInt64

    var publicEntry: ZipEntry {
        ZipEntry(
            path: path,
            compressedSize: compressedSize,
            uncompressedSize: uncompressedSize,
            isDirectory: isDirectory,
            encryption: encryptionStrength?.entryEncryption ?? .none
        )
    }
}

extension WinZipAESStrength {
    var entryEncryption: ZipEntryEncryption {
        switch self {
        case .aes128: .winZipAES128
        case .aes192: .winZipAES192
        case .aes256: .winZipAES256
        }
    }
}
