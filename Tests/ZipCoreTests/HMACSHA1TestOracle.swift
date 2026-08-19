import CommonCrypto
import Foundation

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
