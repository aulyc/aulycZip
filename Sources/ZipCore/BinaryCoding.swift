import Foundation

extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }
}

struct ByteCursor {
    private let data: Data
    private(set) var offset: Int = 0

    init(data: Data, offset: Int = 0) {
        self.data = data
        self.offset = offset
    }

    var remainingCount: Int {
        data.count - offset
    }

    mutating func readUInt16() throws -> UInt16 {
        let bytes = try read(count: MemoryLayout<UInt16>.size)
        return bytes.withUnsafeBytes { rawBuffer in
            UInt16(littleEndian: rawBuffer.loadUnaligned(as: UInt16.self))
        }
    }

    mutating func readUInt32() throws -> UInt32 {
        let bytes = try read(count: MemoryLayout<UInt32>.size)
        return bytes.withUnsafeBytes { rawBuffer in
            UInt32(littleEndian: rawBuffer.loadUnaligned(as: UInt32.self))
        }
    }

    mutating func readUInt64() throws -> UInt64 {
        let bytes = try read(count: MemoryLayout<UInt64>.size)
        return bytes.withUnsafeBytes { rawBuffer in
            UInt64(littleEndian: rawBuffer.loadUnaligned(as: UInt64.self))
        }
    }

    mutating func read(count: Int) throws -> Data {
        guard count >= 0, remainingCount >= count else {
            throw ZipError.truncatedArchive
        }
        let range = offset..<(offset + count)
        offset += count
        return data.subdata(in: range)
    }

    mutating func skip(_ count: Int) throws {
        _ = try read(count: count)
    }
}
