import Foundation
import Testing
@testable import ZipCore

@Suite("ZIP archive integration")
struct ZipArchiveIntegrationTests {
    @Test("plain ZIP can be created, listed, and extracted")
    func plainRoundTrip() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("问候.txt")
            try Data("你好，aulycZip".utf8).write(to: source)

            try ZipArchive.create(at: fixture.archive, contentsOf: [source], encryption: .none)
            let entries = try ZipArchive.list(fixture.archive)

            #expect(entries.map(\.path) == ["问候.txt"])
            #expect(entries.first?.isEncrypted == false)

            try ZipArchive.extract(fixture.archive, to: fixture.output)
            let restored = try Data(contentsOf: fixture.output.appendingPathComponent("问候.txt"))
            #expect(restored == Data("你好，aulycZip".utf8))
        }
    }

    @Test("folder hierarchy round-trips")
    func folderRoundTrip() throws {
        try withFixture { fixture in
            let folder = fixture.source.appendingPathComponent("资料", isDirectory: true)
            let nested = folder.appendingPathComponent("内部", isDirectory: true)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try Data("secret".utf8).write(to: nested.appendingPathComponent("内容.txt"))

            try ZipArchive.create(at: fixture.archive, contentsOf: [folder], encryption: .none)
            let paths = try ZipArchive.list(fixture.archive).map(\.path)

            #expect(paths.contains("资料/"))
            #expect(paths.contains("资料/内部/"))
            #expect(paths.contains("资料/内部/内容.txt"))

            try ZipArchive.extract(fixture.archive, to: fixture.output)
            let restored = try Data(contentsOf: fixture.output.appendingPathComponent("资料/内部/内容.txt"))
            #expect(restored == Data("secret".utf8))
        }
    }

    @Test("WinZip AES-256 archive round-trips")
    func encryptedRoundTrip() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("机密.txt")
            let original = Data(String(repeating: "confidential-", count: 128).utf8)
            try original.write(to: source)

            try ZipArchive.create(
                at: fixture.archive,
                contentsOf: [source],
                encryption: .winZipAES256(password: "correct horse battery staple")
            )
            let entries = try ZipArchive.list(fixture.archive)
            #expect(entries.first?.isEncrypted == true)
            #expect(entries.first?.encryption == .winZipAES256)

            try ZipArchive.extract(
                fixture.archive,
                to: fixture.output,
                password: "correct horse battery staple"
            )
            #expect(try Data(contentsOf: fixture.output.appendingPathComponent("机密.txt")) == original)
        }
    }

    @Test("a pure-Chinese password encrypts and decrypts an AES-256 archive")
    func pureChinesePasswordRoundTrip() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("中文机密.txt")
            let original = Data("这是一份使用纯中文密码保护的内容。".utf8)
            let password = "中文密码安全测试"
            try original.write(to: source)

            try ZipArchive.create(
                at: fixture.archive,
                contentsOf: [source],
                encryption: .winZipAES256(password: password)
            )
            try ZipArchive.extract(
                fixture.archive,
                to: fixture.output,
                password: password
            )

            #expect(
                try Data(contentsOf: fixture.output.appendingPathComponent("中文机密.txt"))
                    == original
            )
        }
    }

    @Test("wrong password is rejected without writing plaintext")
    func wrongPassword() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("secret.txt")
            try Data("secret".utf8).write(to: source)
            try ZipArchive.create(
                at: fixture.archive,
                contentsOf: [source],
                encryption: .winZipAES256(password: "right-password")
            )

            #expect(throws: ZipError.wrongPassword) {
                try ZipArchive.extract(fixture.archive, to: fixture.output, password: "wrong-password")
            }
            #expect(!FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("secret.txt").path))
        }
    }

    @Test("tampered AES payload fails authentication")
    func tamperedPayload() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("secret.txt")
            try Data(String(repeating: "secret", count: 100).utf8).write(to: source)
            try ZipArchive.create(
                at: fixture.archive,
                contentsOf: [source],
                encryption: .winZipAES256(password: "right-password")
            )

            let record = try #require(try ZipArchiveReader(data: Data(contentsOf: fixture.archive)).records.first)
            var bytes = try Data(contentsOf: fixture.archive)
            let encryptedByte = record.dataOffset + 16 + 2
            bytes[encryptedByte] ^= 0x01
            try bytes.write(to: fixture.archive)

            #expect(throws: ZipError.authenticationFailed) {
                try ZipArchive.extract(fixture.archive, to: fixture.output, password: "right-password")
            }
        }
    }

    @Test("archive output cannot overwrite an input file")
    func rejectsDestinationMatchingSource() throws {
        try withFixture { fixture in
            try Data("original input".utf8).write(to: fixture.archive)
            #expect(throws: ZipError.destinationMatchesSource) {
                try ZipArchive.create(
                    at: fixture.archive,
                    contentsOf: [fixture.archive],
                    encryption: .none
                )
            }
            #expect(try Data(contentsOf: fixture.archive) == Data("original input".utf8))
        }
    }

    @Test("a symbolic-link destination root is rejected")
    func rejectsSymbolicLinkDestinationRoot() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("safe.txt")
            try Data("safe".utf8).write(to: source)
            try ZipArchive.create(at: fixture.archive, contentsOf: [source], encryption: .none)

            let outside = fixture.root.appendingPathComponent("outside", isDirectory: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: fixture.output, withDestinationURL: outside)

            #expect(throws: ZipError.unsafeEntryPath(fixture.output.path)) {
                try ZipArchive.extract(fixture.archive, to: fixture.output)
            }
            #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("safe.txt").path))
        }
    }

    @Test("an existing symbolic-link directory inside the destination is rejected")
    func rejectsSymbolicLinkDirectory() throws {
        try withFixture { fixture in
            let payload = fixture.source.appendingPathComponent("payload", isDirectory: true)
            let linked = payload.appendingPathComponent("linked", isDirectory: true)
            try FileManager.default.createDirectory(at: linked, withIntermediateDirectories: true)
            try Data("do not escape".utf8).write(to: linked.appendingPathComponent("secret.txt"))
            try ZipArchive.create(at: fixture.archive, contentsOf: [payload], encryption: .none)

            let outside = fixture.root.appendingPathComponent("outside", isDirectory: true)
            let outputPayload = fixture.output.appendingPathComponent("payload", isDirectory: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outputPayload, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                at: outputPayload.appendingPathComponent("linked", isDirectory: true),
                withDestinationURL: outside
            )

            #expect(throws: ZipError.self) {
                try ZipArchive.extract(fixture.archive, to: fixture.output)
            }
            #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("secret.txt").path))
        }
    }

    @Test("duplicate entry paths are rejected")
    func rejectsDuplicateEntryPaths() throws {
        try withFixture { fixture in
            let first = fixture.source.appendingPathComponent("a.txt")
            let second = fixture.source.appendingPathComponent("b.txt")
            try Data("first".utf8).write(to: first)
            try Data("second".utf8).write(to: second)
            try ZipArchive.create(at: fixture.archive, contentsOf: [first, second], encryption: .none)

            var bytes = try Data(contentsOf: fixture.archive)
            replaceAll(Data("b.txt".utf8), with: Data("a.txt".utf8), in: &bytes)
            try bytes.write(to: fixture.archive)

            #expect(throws: ZipError.duplicateEntry("a.txt")) {
                _ = try ZipArchive.list(fixture.archive)
            }
        }
    }
}

private struct Fixture {
    let root: URL
    let source: URL
    let output: URL
    let archive: URL
}

private func withFixture(_ body: (Fixture) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aulycZip-tests-\(UUID().uuidString)", isDirectory: true)
    let source = root.appendingPathComponent("source", isDirectory: true)
    let output = root.appendingPathComponent("output", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(Fixture(
        root: root,
        source: source,
        output: output,
        archive: root.appendingPathComponent("archive.zip")
    ))
}

private func replaceAll(_ old: Data, with replacement: Data, in data: inout Data) {
    precondition(old.count == replacement.count)
    guard old.count <= data.count else { return }
    for offset in stride(from: data.count - old.count, through: 0, by: -1) {
        if data[offset..<(offset + old.count)] == old[...] {
            data.replaceSubrange(offset..<(offset + old.count), with: replacement)
        }
    }
}
