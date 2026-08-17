import Foundation
import Testing
@testable import ZipCore

@Suite("Raw DEFLATE codec")
struct RawDeflateTests {
    @Test("text round-trips through raw DEFLATE")
    func textRoundTrip() throws {
        let original = Data(String(repeating: "aulycZip-中文-", count: 1_000).utf8)
        let compressed = try RawDeflate.compress(original)
        let restored = try RawDeflate.decompress(compressed, outputLimit: original.count)

        #expect(restored == original)
        #expect(compressed.count < original.count)
    }

    @Test("empty content round-trips")
    func emptyRoundTrip() throws {
        let compressed = try RawDeflate.compress(Data())
        #expect(try RawDeflate.decompress(compressed, outputLimit: 1) == Data())
    }

    @Test("decompression stops at the configured output limit")
    func outputLimit() throws {
        let original = Data(repeating: 0x41, count: 32_768)
        let compressed = try RawDeflate.compress(original)
        #expect(throws: ZipError.outputLimitExceeded) {
            _ = try RawDeflate.decompress(compressed, outputLimit: 1_024)
        }
    }
}
