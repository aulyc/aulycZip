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

        var output = Data(repeating: 0, count: kCCBlockSizeAES128)
        var bytesMoved = 0
        let outputCount = output.count
        let status = output.withUnsafeMutableBytes { outputBytes in
            block.withUnsafeBytes { blockBytes in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode),
                        keyBytes.baseAddress,
                        key.count,
                        nil,
                        blockBytes.baseAddress,
                        block.count,
                        outputBytes.baseAddress,
                        outputCount,
                        &bytesMoved
                    )
                }
            }
        }
        guard status == kCCSuccess, bytesMoved == kCCBlockSizeAES128 else {
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
        var output = Data(capacity: input.count)
        for byte in input {
            if keyStreamOffset == keyStream.count {
                try refillKeyStream()
            }
            output.append(byte ^ keyStream[keyStreamOffset])
            keyStreamOffset += 1
        }
        return output
    }

    private mutating func refillKeyStream() throws {
        guard counter != 0 else {
            throw ZipError.unsupportedFeature("WinZip AES counter exhausted")
        }
        var block = Data()
        block.appendLittleEndian(counter)
        block.append(Data(repeating: 0, count: kCCBlockSizeAES128 - MemoryLayout<UInt32>.size))
        keyStream = try cipher.encrypt(block: block)
        keyStreamOffset = 0
        counter &+= 1
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
