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

    @Test("streaming codec preserves state across chunk boundaries")
    func streamingRoundTrip() throws {
        let original = Data(String(repeating: "streaming-deflate-中文-", count: 8_000).utf8)
        var compressed = Data()
        var encoder = try RawDeflateEncoder { compressed.append($0) }
        try encoder.update(original.prefix(13))
        try encoder.update(original.dropFirst(13).prefix(70_001))
        try encoder.update(original.dropFirst(70_014))
        try encoder.finalize()

        var restored = Data()
        var decoder = try RawDeflateDecoder(outputLimit: UInt64(original.count)) {
            restored.append($0)
        }
        try decoder.update(compressed.prefix(5))
        try decoder.update(compressed.dropFirst(5))
        try decoder.finalize()

        #expect(restored == original)
    }

    @Test("streaming decoder enforces its actual output limit")
    func streamingOutputLimit() throws {
        let original = Data(repeating: 0x5A, count: 100_000)
        let compressed = try RawDeflate.compress(original)
        var decoder = try RawDeflateDecoder(outputLimit: 1_024) { _ in }

        #expect(throws: ZipError.outputLimitExceeded) {
            try decoder.update(compressed)
            try decoder.finalize()
        }
    }
}
