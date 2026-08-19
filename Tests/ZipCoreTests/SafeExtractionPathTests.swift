import Foundation
import Testing
@testable import ZipCore

@Suite("Safe ZIP extraction paths")
struct SafeExtractionPathTests {
    @Test("normal nested path remains below destination")
    func acceptsNormalPath() throws {
        let root = URL(fileURLWithPath: "/tmp/aulyczip-safe-root", isDirectory: true)
        let result = try SafeExtractionPath.resolve("folder/文件.txt", below: root)
        #expect(result.path == "/tmp/aulyczip-safe-root/folder/文件.txt")
    }

    @Test(arguments: [
        "../secret.txt",
        "folder/../../secret.txt",
        "/etc/passwd",
        "folder\\..\\secret.txt",
        "\u{0000}bad.txt",
    ])
    func rejectsUnsafePaths(_ path: String) {
        let root = URL(fileURLWithPath: "/tmp/aulyczip-safe-root", isDirectory: true)
        #expect(throws: ZipError.unsafeEntryPath(path)) {
            _ = try SafeExtractionPath.resolve(path, below: root)
        }
    }

    @Test("an existing symbolic-link parent is rejected")
    func rejectsExistingSymbolicLinkParent() throws {
        try withTemporaryExtractionRoot { root in
            let outside = root.deletingLastPathComponent()
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let link = root.appendingPathComponent("linked", isDirectory: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: outside) }
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
            let output = link.appendingPathComponent("escaped.txt")

            #expect(throws: ZipError.unsafeEntryPath(output.path)) {
                try ZipArchive.createParents(for: output, below: root)
            }
        }
    }

    @Test("an existing symbolic-link directory entry is rejected")
    func rejectsExistingSymbolicLinkDirectory() throws {
        try withTemporaryExtractionRoot { root in
            let outside = root.deletingLastPathComponent()
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let link = root.appendingPathComponent("linked", isDirectory: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: outside) }
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

            #expect(throws: ZipError.unsafeEntryPath(link.path)) {
                try ZipArchive.createDirectory(at: link, below: root)
            }
        }
    }
}

private func withTemporaryExtractionRoot(_ body: (URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aulycZip-path-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(root)
}
