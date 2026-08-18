import Testing
@testable import ZipCore

@Suite("ZIP64 writer boundaries")
struct ZipArchiveWriterBoundaryTests {
    @Test("reserved 32-bit sentinel values switch to ZIP64 without integer traps")
    func sizeAndOffsetBoundaries() {
        let largestClassic = UInt64(UInt32.max) - 1
        #expect(!ZipArchiveWriter.zip64Requirements(
            compressedSize: largestClassic,
            uncompressedSize: largestClassic,
            localHeaderOffset: largestClassic,
            force: false
        ).usesZIP64)

        let sizeBoundary = ZipArchiveWriter.zip64Requirements(
            compressedSize: UInt64(UInt32.max),
            uncompressedSize: 1,
            localHeaderOffset: 1,
            force: false
        )
        #expect(sizeBoundary.sizeFields)
        #expect(!sizeBoundary.offsetField)

        let offsetBoundary = ZipArchiveWriter.zip64Requirements(
            compressedSize: 1,
            uncompressedSize: 1,
            localHeaderOffset: UInt64(UInt32.max),
            force: false
        )
        #expect(!offsetBoundary.sizeFields)
        #expect(offsetBoundary.offsetField)
    }
}
