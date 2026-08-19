import Darwin
import Foundation
import Testing
@testable import ZipCore

private let runZipCoreBenchmarks = ProcessInfo.processInfo.environment[
    "AULYCZIP_RUN_BENCHMARKS"
] == "1"

@Suite(
    "ZIP streaming benchmark",
    .enabled(
        if: runZipCoreBenchmarks,
        "Run scripts/benchmark-zipcore.sh to enable the fixed streaming benchmark"
    )
)
struct ZipCoreBenchmarkTests {
    @Test("large AES streaming create and extract baseline")
    func aesRoundTripBenchmark() throws {
        let byteCount = UInt64(
            ProcessInfo.processInfo.environment["AULYCZIP_BENCHMARK_BYTES"]
                .flatMap(UInt64.init) ?? 200 * 1024 * 1024
        )
        let maximumPeakResidentBytes = Int64(
            ProcessInfo.processInfo.environment["AULYCZIP_BENCHMARK_MAX_RSS_BYTES"]
                .flatMap(Int64.init) ?? 192 * 1024 * 1024
        )
        let maximumCreateSeconds = Int64(
            ProcessInfo.processInfo.environment["AULYCZIP_BENCHMARK_MAX_CREATE_SECONDS"]
                .flatMap(Int64.init) ?? 30
        )
        let maximumExtractSeconds = Int64(
            ProcessInfo.processInfo.environment["AULYCZIP_BENCHMARK_MAX_EXTRACT_SECONDS"]
                .flatMap(Int64.init) ?? 30
        )
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "aulycZip-benchmark-\(UUID().uuidString)",
            isDirectory: true
        )
        let source = root.appendingPathComponent("source.bin")
        let archive = root.appendingPathComponent("benchmark.zip")
        let output = root.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writeBenchmarkFile(at: source, byteCount: byteCount)

        let createStart = ContinuousClock.now
        try ZipArchive.create(
            at: archive,
            contentsOf: [source],
            encryption: .winZipAES256(password: "aulycZip-benchmark-password")
        )
        let createDuration = createStart.duration(to: .now)
        let extractStart = ContinuousClock.now
        try ZipArchive.extract(
            archive,
            to: output,
            password: "aulycZip-benchmark-password",
            limits: ZipExtractionLimits(
                maximumEntryCount: 10,
                maximumEntryUncompressedSize: byteCount,
                maximumTotalUncompressedSize: byteCount
            )
        )
        let extractDuration = extractStart.duration(to: .now)
        let peakResidentBytes = currentProcessPeakResidentBytes()

        let restored = output.appendingPathComponent("source.bin")
        let archiveByteCount = UInt64(
            try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        )
        let minimumArchiveByteCount = byteCount - byteCount / 20
        #expect(try restored.resourceValues(forKeys: [.fileSizeKey]).fileSize == Int(byteCount))
        #expect(archiveByteCount >= minimumArchiveByteCount)
        #expect(peakResidentBytes > 0)
        #expect(peakResidentBytes <= maximumPeakResidentBytes)
        #expect(createDuration <= .seconds(maximumCreateSeconds))
        #expect(extractDuration <= .seconds(maximumExtractSeconds))
        print(
            "aulycZip benchmark bytes=\(byteCount) archive_bytes=\(archiveByteCount) "
                + "create=\(createDuration) "
                + "extract=\(extractDuration) process_peak_rss_bytes=\(peakResidentBytes)"
        )
    }
}

private func currentProcessPeakResidentBytes() -> Int64 {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return -1 }
    return Int64(usage.ru_maxrss)
}

private func writeBenchmarkFile(at url: URL, byteCount: UInt64) throws {
    guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
        throw ZipError.invalidArchive("Unable to create benchmark input")
    }
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    var generator = DeterministicHighEntropyGenerator()
    var remaining = byteCount
    while remaining > 0 {
        let count = Int(min(1024 * 1024, remaining))
        var chunk = Data(count: count)
        chunk.withUnsafeMutableBytes { buffer in
            var offset = 0
            while offset + MemoryLayout<UInt64>.size <= buffer.count {
                buffer.storeBytes(
                    of: generator.next().littleEndian,
                    toByteOffset: offset,
                    as: UInt64.self
                )
                offset += MemoryLayout<UInt64>.size
            }
            if offset < buffer.count {
                var tail = generator.next()
                while offset < buffer.count {
                    buffer[offset] = UInt8(truncatingIfNeeded: tail)
                    tail >>= 8
                    offset += 1
                }
            }
        }
        try handle.write(contentsOf: chunk)
        remaining -= UInt64(count)
    }
    try handle.synchronize()
}

private struct DeterministicHighEntropyGenerator {
    // Test-only SplitMix64 stream for reproducible incompressible input. It is
    // never used for passwords, keys, salts, or other security decisions.
    private var state: UInt64 = 0xA17C_21B5_4D8E_9307

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
