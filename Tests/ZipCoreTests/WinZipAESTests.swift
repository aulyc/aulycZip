import Foundation
import Testing
@testable import ZipCore

@Suite("WinZip AES primitives")
struct WinZipAESTests {
    @Test("PBKDF2-HMAC-SHA1 matches RFC 6070")
    func pbkdf2Vector() throws {
        let derived = try PBKDF2SHA1.derive(
            password: Data("password".utf8),
            salt: Data("salt".utf8),
            iterations: 1,
            outputByteCount: 20
        )
        #expect(derived.hexString == "0c60c80f961f0e71f3a9b524af6012062fe037a6")
    }

    @Test("AES-256 block encryption matches NIST SP 800-38A")
    func aesBlockVector() throws {
        let key = try #require(Data(hex: "603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4"))
        let plaintext = try #require(Data(hex: "6bc1bee22e409f96e93d7e117393172a"))
        let cipher = try AESBlockCipher(key: key)
        #expect(try cipher.encrypt(block: plaintext).hexString == "f3eed1bdb5d2a03c064b5a7e3db181f8")
    }

    @Test("AES block cipher processes multiple counter blocks in one call")
    func aesBatchVector() throws {
        let key = try #require(Data(hex: "603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4"))
        let plaintext = try #require(Data(hex: "6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51"))
        let cipher = try AESBlockCipher(key: key)

        #expect(
            try cipher.encrypt(blocks: plaintext).hexString
                == "f3eed1bdb5d2a03c064b5a7e3db181f8591ccb10d410ed26dc5ba74a31362870"
        )
    }

    @Test("WinZip AES counter stream is reversible across chunk boundaries")
    func counterStreamRoundTrip() throws {
        let key = Data((0..<32).map(UInt8.init))
        let plaintext = Data((0..<251).map { UInt8($0 & 0xFF) })

        var encryptor = try WinZipAESCTR(key: key)
        let encrypted = try encryptor.update(plaintext.prefix(7))
            + encryptor.update(plaintext.dropFirst(7).prefix(81))
            + encryptor.update(plaintext.dropFirst(88))

        var decryptor = try WinZipAESCTR(key: key)
        let decrypted = try decryptor.update(encrypted.prefix(19))
            + decryptor.update(encrypted.dropFirst(19))

        #expect(encrypted != plaintext)
        #expect(decrypted == plaintext)
    }

    @Test("AES-256 key material has WinZip-compatible sizes")
    func keyMaterialSizes() throws {
        let material = try WinZipAESKeyMaterial.derive(
            password: "correct horse battery staple",
            salt: Data(repeating: 0xA5, count: 16),
            strength: .aes256
        )
        #expect(material.encryptionKey.count == 32)
        #expect(material.authenticationKey.count == 32)
        #expect(material.passwordVerification.count == 2)
    }

    @Test("incremental HMAC matches one-shot authentication")
    func incrementalHMAC() {
        let key = Data("authentication-key".utf8)
        let payload = Data(String(repeating: "encrypted-payload", count: 1_000).utf8)
        let context = HMACSHA1Context(key: key)
        context.update(payload.prefix(17))
        context.update(payload.dropFirst(17))

        #expect(context.finalize() == HMACSHA1.authenticationCode(for: payload, key: key))
    }
}

private extension Data {
    init?(hex: String) {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var value = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            value.append(byte)
            index = next
        }
        self = value
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
