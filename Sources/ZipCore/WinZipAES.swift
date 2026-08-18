import CommonCrypto
import Foundation

enum PBKDF2SHA1 {
    static func derive(
        password: Data,
        salt: Data,
        iterations: Int,
        outputByteCount: Int
    ) throws -> Data {
        guard iterations > 0, iterations <= Int(UInt32.max), outputByteCount > 0 else {
            throw ZipError.invalidArchive("Invalid password derivation parameters")
        }

        var output = Data(repeating: 0, count: outputByteCount)
        let status = output.withUnsafeMutableBytes { outputBytes in
            password.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        password.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        UInt32(iterations),
                        outputBytes.bindMemory(to: UInt8.self).baseAddress,
                        outputByteCount
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw ZipError.invalidArchive("Password derivation failed")
        }
        return output
    }
}

struct AESBlockCipher {
    private let key: Data

    init(key: Data) throws {
        guard [kCCKeySizeAES128, kCCKeySizeAES192, kCCKeySizeAES256].contains(key.count) else {
            throw ZipError.invalidArchive("Invalid AES key size")
        }
        self.key = key
    }

    func encrypt(block: Data) throws -> Data {
        guard block.count == kCCBlockSizeAES128 else {
            throw ZipError.invalidArchive("AES block must be 16 bytes")
        }

        return try encrypt(blocks: block)
    }

    func encrypt(blocks: Data) throws -> Data {
        guard !blocks.isEmpty, blocks.count.isMultiple(of: kCCBlockSizeAES128) else {
            throw ZipError.invalidArchive("AES input must contain complete blocks")
        }

        var output = Data(repeating: 0, count: blocks.count)
        var bytesMoved = 0
        let outputCount = output.count
        let status = output.withUnsafeMutableBytes { outputBytes in
            blocks.withUnsafeBytes { blockBytes in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode),
                        keyBytes.baseAddress,
                        key.count,
                        nil,
                        blockBytes.baseAddress,
                        blocks.count,
                        outputBytes.baseAddress,
                        outputCount,
                        &bytesMoved
                    )
                }
            }
        }
        guard status == kCCSuccess, bytesMoved == blocks.count else {
            throw ZipError.invalidArchive("AES block encryption failed")
        }
        return output
    }
}

struct WinZipAESCTR {
    private let cipher: AESBlockCipher
    private var counter: UInt32 = 1
    private var keyStream = Data()
    private var keyStreamOffset = 0

    init(key: Data) throws {
        cipher = try AESBlockCipher(key: key)
    }

    mutating func update<D: DataProtocol>(_ input: D) throws -> Data {
        let contiguous = Data(input)
        var output = Data(repeating: 0, count: contiguous.count)
        var inputOffset = 0
        while inputOffset < contiguous.count {
            if keyStreamOffset == keyStream.count {
                try refillKeyStream()
            }
            let count = min(
                contiguous.count - inputOffset,
                keyStream.count - keyStreamOffset
            )
            output.withUnsafeMutableBytes { outputBytes in
                contiguous.withUnsafeBytes { inputBytes in
                    keyStream.withUnsafeBytes { keyStreamBytes in
                        let outputBase = outputBytes.bindMemory(to: UInt8.self).baseAddress!
                        let inputBase = inputBytes.bindMemory(to: UInt8.self).baseAddress!
                        let keyStreamBase = keyStreamBytes.bindMemory(to: UInt8.self).baseAddress!
                        for index in 0..<count {
                            outputBase[inputOffset + index] = inputBase[inputOffset + index]
                                ^ keyStreamBase[keyStreamOffset + index]
                        }
                    }
                }
            }
            inputOffset += count
            keyStreamOffset += count
        }
        return output
    }

    private mutating func refillKeyStream() throws {
        guard counter != 0 else {
            throw ZipError.unsupportedFeature("WinZip AES counter exhausted")
        }
        let remainingBlocks = UInt64(UInt32.max) - UInt64(counter) + 1
        let blockCount = Int(min(4_096, remainingBlocks))
        var blocks = Data(capacity: blockCount * kCCBlockSizeAES128)
        for _ in 0..<blockCount {
            blocks.appendLittleEndian(counter)
            blocks.append(Data(repeating: 0, count: kCCBlockSizeAES128 - MemoryLayout<UInt32>.size))
            counter &+= 1
        }
        keyStream = try cipher.encrypt(blocks: blocks)
        keyStreamOffset = 0
    }
}

public enum WinZipAESStrength: UInt8, Sendable {
    case aes128 = 1
    case aes192 = 2
    case aes256 = 3

    var keyByteCount: Int {
        switch self {
        case .aes128: 16
        case .aes192: 24
        case .aes256: 32
        }
    }

    var saltByteCount: Int {
        keyByteCount / 2
    }
}

public struct WinZipAESKeyMaterial: Sendable {
    public let encryptionKey: Data
    public let authenticationKey: Data
    public let passwordVerification: Data

    public static func derive(
        password: String,
        salt: Data,
        strength: WinZipAESStrength
    ) throws -> WinZipAESKeyMaterial {
        guard salt.count == strength.saltByteCount else {
            throw ZipError.invalidArchive("Invalid WinZip AES salt size")
        }

        let keyLength = strength.keyByteCount
        let derived = try PBKDF2SHA1.derive(
            password: Data(password.utf8),
            salt: salt,
            iterations: 1_000,
            outputByteCount: keyLength * 2 + 2
        )
        return WinZipAESKeyMaterial(
            encryptionKey: derived.prefix(keyLength),
            authenticationKey: derived.dropFirst(keyLength).prefix(keyLength),
            passwordVerification: derived.suffix(2)
        )
    }
}
