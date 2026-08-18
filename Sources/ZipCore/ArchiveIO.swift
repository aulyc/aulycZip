import Foundation

protocol ArchiveByteSource {
    var size: UInt64 { get }
    func read(offset: UInt64, count: Int) throws -> Data
}

final class FileArchiveSource: ArchiveByteSource {
    let size: UInt64
    private let handle: FileHandle

    init(url: URL) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else {
            throw ZipError.invalidArchive("ZIP source is not a regular file")
        }
        guard let byteCount = values.fileSize, byteCount >= 0 else {
            throw ZipError.invalidArchive("ZIP source size is unavailable")
        }
        size = UInt64(byteCount)
        handle = try FileHandle(forReadingFrom: url)
    }

    deinit {
        try? handle.close()
    }

    func read(offset: UInt64, count: Int) throws -> Data {
        guard count >= 0,
              offset <= size,
              UInt64(count) <= size - offset else {
            throw ZipError.truncatedArchive
        }
        try handle.seek(toOffset: offset)
        let data = try handle.read(upToCount: count) ?? Data()
        guard data.count == count else {
            throw ZipError.truncatedArchive
        }
        return data
    }
}

struct DataArchiveSource: ArchiveByteSource {
    let data: Data

    var size: UInt64 { UInt64(data.count) }

    func read(offset: UInt64, count: Int) throws -> Data {
        guard count >= 0,
              offset <= size,
              UInt64(count) <= size - offset,
              offset <= UInt64(Int.max) else {
            throw ZipError.truncatedArchive
        }
        let start = Int(offset)
        return data.subdata(in: start..<(start + count))
    }
}

extension ArchiveByteSource {
    func forEachChunk(
        offset: UInt64,
        length: UInt64,
        chunkSize: Int = 64 * 1024,
        _ body: (Data) throws -> Void
    ) throws {
        guard chunkSize > 0, offset <= size, length <= size - offset else {
            throw ZipError.truncatedArchive
        }
        var cursor = offset
        var remaining = length
        while remaining > 0 {
            let count = Int(min(UInt64(chunkSize), remaining))
            try autoreleasepool {
                try body(read(offset: cursor, count: count))
            }
            cursor += UInt64(count)
            remaining -= UInt64(count)
        }
    }
}

enum ArchiveFileIO {
    static let chunkSize = 64 * 1024

    static func createPrivateDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
    }

    static func createPrivateFile(at url: URL) throws -> FileHandle {
        guard FileManager.default.createFile(
            atPath: url.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw ZipError.invalidArchive("Unable to create temporary archive file")
        }
        return try FileHandle(forWritingTo: url)
    }

    static func copy(
        from source: URL,
        to destination: FileHandle,
        cancellation: ZipOperationCancellation? = nil
    ) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        while true {
            let reachedEnd = try autoreleasepool { () throws -> Bool in
                guard let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty else {
                    return true
                }
                try cancellation?.check()
                try destination.write(contentsOf: chunk)
                return false
            }
            if reachedEnd { break }
        }
    }

    static func stream(from source: URL, _ body: (Data) throws -> Void) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        while true {
            let reachedEnd = try autoreleasepool { () throws -> Bool in
                guard let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty else {
                    return true
                }
                try body(chunk)
                return false
            }
            if reachedEnd { break }
        }
    }
}
