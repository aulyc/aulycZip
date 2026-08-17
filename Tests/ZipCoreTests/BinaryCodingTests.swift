import Foundation
import Testing
@testable import ZipCore

@Suite("ZIP binary coding")
struct BinaryCodingTests {
    @Test("little-endian integers round-trip")
    func littleEndianRoundTrip() throws {
        var data = Data()
        data.appendLittleEndian(UInt16(0x1234))
        data.appendLittleEndian(UInt32(0x89ABCDEF))

        var cursor = ByteCursor(data: data)
        #expect(try cursor.readUInt16() == 0x1234)
        #expect(try cursor.readUInt32() == 0x89ABCDEF)
        #expect(cursor.remainingCount == 0)
    }

    @Test("truncated data is rejected")
    func truncatedDataIsRejected() {
        var cursor = ByteCursor(data: Data([0x01]))
        #expect(throws: ZipError.truncatedArchive) {
            _ = try cursor.readUInt16()
        }
    }
}
