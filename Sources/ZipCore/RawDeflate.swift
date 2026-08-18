import Compression
import Foundation

private final class RawDeflateStream {
    private static let chunkSize = 64 * 1024

    private var stream: compression_stream
    private let outputLimit: UInt64
    private let output: (Data) throws -> Void
    private var outputCount: UInt64 = 0
    private var finished = false

    init(
        operation: compression_stream_operation,
        outputLimit: UInt64,
        output: @escaping (Data) throws -> Void
    ) throws {
        let sentinel = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        defer { sentinel.deallocate() }
        stream = compression_stream(
            dst_ptr: sentinel,
            dst_size: 0,
            src_ptr: UnsafePointer(sentinel),
            src_size: 0,
            state: nil
        )
        guard compression_stream_init(&stream, operation, COMPRESSION_ZLIB) != COMPRESSION_STATUS_ERROR else {
            throw ZipError.invalidArchive("Unable to initialize DEFLATE codec")
        }
        self.outputLimit = outputLimit
        self.output = output
    }

    deinit {
        compression_stream_destroy(&stream)
    }

    func update<D: DataProtocol>(_ input: D) throws {
        guard !finished else {
            throw ZipError.invalidArchive("DEFLATE stream has already ended")
        }
        guard !input.isEmpty else { return }
        let data = Data(input)
        try data.withUnsafeBytes { sourceBytes in
            guard let source = sourceBytes.bindMemory(to: UInt8.self).baseAddress else { return }
            stream.src_ptr = source
            stream.src_size = data.count
            while stream.src_size > 0 {
                let status = try process(flags: 0)
                if status == COMPRESSION_STATUS_END {
                    finished = true
                    guard stream.src_size == 0 else {
                        throw ZipError.invalidArchive("DEFLATE stream contains trailing data")
                    }
                    break
                }
            }
        }
    }

    func finalize() throws {
        guard !finished else { return }
        var sentinel: UInt8 = 0
        try withUnsafePointer(to: &sentinel) { pointer in
            stream.src_ptr = pointer
            stream.src_size = 0
            while true {
                let status = try process(flags: Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                if status == COMPRESSION_STATUS_END {
                    finished = true
                    return
                }
            }
        }
    }

    private func process(flags: Int32) throws -> compression_status {
        var destination = [UInt8](repeating: 0, count: Self.chunkSize)
        let status = destination.withUnsafeMutableBytes { destinationBytes in
            stream.dst_ptr = destinationBytes.bindMemory(to: UInt8.self).baseAddress!
            stream.dst_size = Self.chunkSize
            return compression_stream_process(&stream, flags)
        }
        let produced = Self.chunkSize - stream.dst_size
        if produced > 0 {
            let produced64 = UInt64(produced)
            guard outputCount <= outputLimit, produced64 <= outputLimit - outputCount else {
                throw ZipError.outputLimitExceeded
            }
            outputCount += produced64
            try output(Data(destination.prefix(produced)))
        }
        guard status == COMPRESSION_STATUS_OK || status == COMPRESSION_STATUS_END else {
            throw ZipError.invalidArchive("Invalid DEFLATE stream")
        }
        return status
    }
}

struct RawDeflateEncoder {
    private let stream: RawDeflateStream

    init(output: @escaping (Data) throws -> Void) throws {
        stream = try RawDeflateStream(
            operation: COMPRESSION_STREAM_ENCODE,
            outputLimit: .max,
            output: output
        )
    }

    mutating func update<D: DataProtocol>(_ input: D) throws {
        try stream.update(input)
    }

    mutating func finalize() throws {
        try stream.finalize()
    }
}

struct RawDeflateDecoder {
    private let stream: RawDeflateStream

    init(outputLimit: UInt64, output: @escaping (Data) throws -> Void) throws {
        stream = try RawDeflateStream(
            operation: COMPRESSION_STREAM_DECODE,
            outputLimit: outputLimit,
            output: output
        )
    }

    mutating func update<D: DataProtocol>(_ input: D) throws {
        try stream.update(input)
    }

    mutating func finalize() throws {
        try stream.finalize()
    }
}

public enum RawDeflate {
    public static func compress(_ data: Data) throws -> Data {
        var result = Data()
        var encoder = try RawDeflateEncoder { result.append($0) }
        try encoder.update(data)
        try encoder.finalize()
        return result
    }

    public static func decompress(_ data: Data, outputLimit: Int) throws -> Data {
        guard outputLimit >= 0 else {
            throw ZipError.outputLimitExceeded
        }
        var result = Data()
        var decoder = try RawDeflateDecoder(outputLimit: UInt64(outputLimit)) { result.append($0) }
        try decoder.update(data)
        try decoder.finalize()
        return result
    }
}
