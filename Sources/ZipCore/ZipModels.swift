import Foundation

public enum ZipCreationEncryption: Sendable {
    case none
    case winZipAES256(password: String)
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
    let compressedSize: UInt32
    let uncompressedSize: UInt32
    let crc32: UInt32
    let compressionMethod: UInt16
    let flags: UInt16
    let isDirectory: Bool
    let encryptionStrength: WinZipAESStrength?
    let aesVendorVersion: UInt16?
    let localHeaderOffset: UInt32
    let dataOffset: Int

    var publicEntry: ZipEntry {
        ZipEntry(
            path: path,
            compressedSize: UInt64(compressedSize),
            uncompressedSize: UInt64(uncompressedSize),
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
