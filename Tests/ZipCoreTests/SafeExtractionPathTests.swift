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
}
