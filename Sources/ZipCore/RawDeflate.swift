import Compression
import Foundation

public enum RawDeflate {
    public static func compress(_ data: Data) throws -> Data {
        try process(data, operation: COMPRESSION_STREAM_ENCODE, outputLimit: .max)
    }

    public static func decompress(_ data: Data, outputLimit: Int) throws -> Data {
        guard outputLimit >= 0 else {
            throw ZipError.outputLimitExceeded
        }
        return try process(data, operation: COMPRESSION_STREAM_DECODE, outputLimit: outputLimit)
    }

    private static func process(
        _ data: Data,
        operation: compression_stream_operation,
        outputLimit: Int
    ) throws -> Data {
        let dummyDestination = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        let dummySource = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        defer {
            dummyDestination.deallocate()
            dummySource.deallocate()
        }

        var stream = compression_stream(
            dst_ptr: dummyDestination,
            dst_size: 0,
            src_ptr: UnsafePointer(dummySource),
            src_size: 0,
            state: nil
        )
        guard compression_stream_init(&stream, operation, COMPRESSION_ZLIB) != COMPRESSION_STATUS_ERROR else {
            throw ZipError.invalidArchive("Unable to initialize DEFLATE codec")
        }
        defer { compression_stream_destroy(&stream) }

        let source = data.isEmpty ? Data([0]) : data
        return try source.withUnsafeBytes { sourceBytes in
            stream.src_ptr = sourceBytes.bindMemory(to: UInt8.self).baseAddress!
            stream.src_size = data.count

            var result = Data()
            let chunkSize = 64 * 1024
            var destination = [UInt8](repeating: 0, count: chunkSize)
            let flags = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)

            while true {
                let status = destination.withUnsafeMutableBytes { destinationBytes in
                    stream.dst_ptr = destinationBytes.bindMemory(to: UInt8.self).baseAddress!
                    stream.dst_size = chunkSize
                    return compression_stream_process(&stream, flags)
                }

                let produced = chunkSize - stream.dst_size
                if produced > 0 {
                    guard result.count <= outputLimit - produced else {
                        throw ZipError.outputLimitExceeded
                    }
                    result.append(contentsOf: destination.prefix(produced))
                }

                switch status {
                case COMPRESSION_STATUS_END:
                    return result
                case COMPRESSION_STATUS_OK:
                    continue
                default:
                    throw ZipError.invalidArchive("Invalid DEFLATE stream")
                }
            }
        }
    }
}
