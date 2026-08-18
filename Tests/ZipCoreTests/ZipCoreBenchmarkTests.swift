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
        #expect(try restored.resourceValues(forKeys: [.fileSizeKey]).fileSize == Int(byteCount))
        print(
            "aulycZip benchmark bytes=\(byteCount) create=\(createDuration) "
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
    let chunk = Data((0..<(1024 * 1024)).map {
        UInt8(truncatingIfNeeded: (($0 &* 1_103_515_245) &+ 12_345) >> 16)
    })
    var remaining = byteCount
    while remaining > 0 {
        let count = Int(min(UInt64(chunk.count), remaining))
        try handle.write(contentsOf: chunk.prefix(count))
        remaining -= UInt64(count)
    }
    try handle.synchronize()
}
