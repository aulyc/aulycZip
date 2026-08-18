import Foundation

public struct CRC32: Sendable {
    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) == 1
                ? 0xEDB8_8320 ^ (value >> 1)
                : value >> 1
        }
        return value
    }

    private var value: UInt32 = 0xFFFF_FFFF

    public init() {}

    public mutating func update(_ data: Data) {
        data.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            for index in bytes.indices {
                let tableIndex = Int((value ^ UInt32(bytes[index])) & 0xFF)
                value = Self.table[tableIndex] ^ (value >> 8)
            }
        }
    }

    public var finalized: UInt32 {
        value ^ 0xFFFF_FFFF
    }

    public static func checksum(_ data: Data) -> UInt32 {
        var crc = CRC32()
        crc.update(data)
        return crc.finalized
    }
}
