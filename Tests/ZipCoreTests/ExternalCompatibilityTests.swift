import Foundation
import Testing
@testable import ZipCore

private let sevenZipPath = ProcessInfo.processInfo.environment["AULYCZIP_7ZZ"]

@Suite("External ZIP compatibility")
struct ExternalCompatibilityTests {
    @Test(
        "7-Zip extracts an aulycZip WinZip AES-256 archive",
        .enabled(if: sevenZipPath != nil, "Set AULYCZIP_7ZZ to run external compatibility tests"),
        arguments: ["aulycZip-known-test-password", "中文密码安全测试"]
    )
    func sevenZipExtractsOurArchive(password: String) throws {
        let sevenZip = try #require(sevenZipPath)

        try withCompatibilityFixture { fixture in
            let source = fixture.source.appendingPathComponent("兼容性.txt")
            let original = Data("WinZip AES interoperability".utf8)
            try original.write(to: source)
            try ZipArchive.create(
                at: fixture.archive,
                contentsOf: [source],
                encryption: .winZipAES256(password: password)
            )

            try run(
                sevenZip,
                arguments: ["x", fixture.archive.path, "-o\(fixture.externalOutput.path)", "-p\(password)", "-y"]
            )
            #expect(try Data(contentsOf: fixture.externalOutput.appendingPathComponent("兼容性.txt")) == original)
        }
    }

    @Test(
        "aulycZip extracts a 7-Zip AES-256 archive",
        .enabled(if: sevenZipPath != nil, "Set AULYCZIP_7ZZ to run external compatibility tests")
    )
    func extractsSevenZipArchive() throws {
        let sevenZip = try #require(sevenZipPath)

        try withCompatibilityFixture { fixture in
            let password = "aulycZip-known-test-password"
            let source = fixture.source.appendingPathComponent("reverse.txt")
            let original = Data(String(repeating: "external-archive-", count: 64).utf8)
            try original.write(to: source)

            try run(
                sevenZip,
                arguments: [
                    "a", "-tzip", "-mem=AES256", "-p\(password)",
                    fixture.archive.path, source.path
                ]
            )
            try ZipArchive.extract(fixture.archive, to: fixture.output, password: password)
            #expect(try Data(contentsOf: fixture.output.appendingPathComponent("reverse.txt")) == original)
        }
    }

    @Test(
        "7-Zip extracts forced ZIP64 plain and AES-256 archives",
        .enabled(if: sevenZipPath != nil, "Set AULYCZIP_7ZZ to run external compatibility tests")
    )
    func sevenZipExtractsZIP64Archives() throws {
        let sevenZip = try #require(sevenZipPath)
        try withCompatibilityFixture { fixture in
            let source = fixture.source.appendingPathComponent("zip64-external.txt")
            let original = Data(String(repeating: "ZIP64 interoperability-", count: 1_000).utf8)
            try original.write(to: source)
            try assertSevenZipExtractsForcedZIP64(
                sevenZip: sevenZip,
                fixture: fixture,
                source: source,
                original: original,
                encryption: .none,
                password: nil
            )
            try assertSevenZipExtractsForcedZIP64(
                sevenZip: sevenZip,
                fixture: fixture,
                source: source,
                original: original,
                encryption: .winZipAES256(password: "aulycZip-known-test-password"),
                password: "aulycZip-known-test-password"
            )
        }
    }
}

private func assertSevenZipExtractsForcedZIP64(
    sevenZip: String,
    fixture: CompatibilityFixture,
    source: URL,
    original: Data,
    encryption: ZipCreationEncryption,
    password: String?
) throws {
    try? FileManager.default.removeItem(at: fixture.archive)
    try? FileManager.default.removeItem(at: fixture.externalOutput)
    try FileManager.default.createDirectory(
        at: fixture.externalOutput,
        withIntermediateDirectories: true
    )
    try ZipArchiveWriter.create(
        at: fixture.archive,
        contentsOf: [source],
        encryption: encryption,
        options: ZipArchiveWriterOptions(forceZIP64: true)
    )

    var arguments = [
        "x", fixture.archive.path, "-o\(fixture.externalOutput.path)", "-y",
    ]
    if let password {
        arguments.append("-p\(password)")
    }
    try run(sevenZip, arguments: arguments)
    #expect(
        try Data(contentsOf: fixture.externalOutput.appendingPathComponent("zip64-external.txt"))
            == original
    )
}

private struct CompatibilityFixture {
    let root: URL
    let source: URL
    let output: URL
    let externalOutput: URL
    let archive: URL
}

private func withCompatibilityFixture(_ body: (CompatibilityFixture) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aulycZip-compatibility-\(UUID().uuidString)", isDirectory: true)
    let source = root.appendingPathComponent("source", isDirectory: true)
    let output = root.appendingPathComponent("output", isDirectory: true)
    let externalOutput = root.appendingPathComponent("external", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(CompatibilityFixture(
        root: root,
        source: source,
        output: output,
        externalOutput: externalOutput,
        archive: root.appendingPathComponent("compatibility.zip")
    ))
}

private func run(_ executable: String, arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    let terminated = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in terminated.signal() }
    try process.run()
    guard terminated.wait(timeout: .now() + 120) == .success else {
        process.terminate()
        throw ZipError.invalidArchive("External compatibility command timed out")
    }
    guard process.terminationStatus == 0 else {
        throw ZipError.invalidArchive("External compatibility command failed with status \(process.terminationStatus)")
    }
}
