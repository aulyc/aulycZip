import CommonCrypto
import Foundation
import Security

enum SecureRandom {
    static func bytes(count: Int) throws -> Data {
        guard count >= 0 else {
            throw ZipError.invalidArchive("Invalid random byte count")
        }
        var data = Data(repeating: 0, count: count)
        let status = data.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, count, bytes.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw ZipError.invalidArchive("Secure random generation failed")
        }
        return data
    }
}

enum HMACSHA1 {
    static func authenticationCode(for data: Data, key: Data) -> Data {
        var output = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        key.withUnsafeBytes { keyBytes in
            data.withUnsafeBytes { dataBytes in
                CCHmac(
                    CCHmacAlgorithm(kCCHmacAlgSHA1),
                    keyBytes.baseAddress,
                    key.count,
                    dataBytes.baseAddress,
                    data.count,
                    &output
                )
            }
        }
        return Data(output)
    }
}

final class HMACSHA1Context {
    private var context = CCHmacContext()
    private var finished = false

    init(key: Data) {
        key.withUnsafeBytes { keyBytes in
            CCHmacInit(
                &context,
                CCHmacAlgorithm(kCCHmacAlgSHA1),
                keyBytes.baseAddress,
                key.count
            )
        }
    }

    func update<D: DataProtocol>(_ data: D) {
        precondition(!finished, "HMAC context has already been finalized")
        let contiguous = Data(data)
        contiguous.withUnsafeBytes { bytes in
            CCHmacUpdate(&context, bytes.baseAddress, contiguous.count)
        }
    }

    func finalize() -> Data {
        precondition(!finished, "HMAC context has already been finalized")
        finished = true
        var output = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        CCHmacFinal(&context, &output)
        return Data(output)
    }
}

enum ConstantTime {
    static func equals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) {
            difference |= left ^ right
        }
        return difference == 0
    }
}
