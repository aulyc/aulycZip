import Foundation
import Testing
@testable import ZipCore

@Suite("External ZIP compatibility")
struct ExternalCompatibilityTests {
    @Test(
        "7-Zip extracts an aulycZip WinZip AES-256 archive",
        arguments: ["aulycZip-known-test-password", "中文密码安全测试"]
    )
    func sevenZipExtractsOurArchive(password: String) throws {
        guard let sevenZip = ProcessInfo.processInfo.environment["AULYCZIP_7ZZ"] else {
            return
        }

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

    @Test("aulycZip extracts a 7-Zip AES-256 archive")
    func extractsSevenZipArchive() throws {
        guard let sevenZip = ProcessInfo.processInfo.environment["AULYCZIP_7ZZ"] else {
            return
        }

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
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw ZipError.invalidArchive("External compatibility command failed with status \(process.terminationStatus)")
    }
}
