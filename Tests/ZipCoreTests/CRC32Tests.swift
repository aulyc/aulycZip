import Foundation
import Testing
@testable import ZipCore

@Suite("CRC-32")
struct CRC32Tests {
    @Test("standard check value matches PKZIP CRC-32")
    func standardCheckValue() {
        let value = CRC32.checksum(Data("123456789".utf8))
        #expect(value == 0xCBF4_3926)
    }

    @Test("streaming updates match one-shot checksum")
    func streamingUpdates() {
        var crc = CRC32()
        crc.update(Data("1234".utf8))
        crc.update(Data("56789".utf8))
        #expect(crc.finalized == 0xCBF4_3926)
    }
}
