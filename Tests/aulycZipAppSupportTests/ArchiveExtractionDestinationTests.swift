import Foundation
import Testing
@testable import aulycZipAppSupport

@Suite("Archive extraction destination")
struct ArchiveExtractionDestinationTests {
    @Test("a new extraction folder uses the preferred archive name")
    func usesPreferredName() throws {
        try withTemporaryDirectory { root in
            let destination = ArchiveExtractionDestination.unique(
                below: root,
                preferredName: "资料"
            )

            #expect(destination == root.appendingPathComponent("资料", isDirectory: true))
        }
    }

    @Test("existing extraction folders receive the next numeric suffix")
    func avoidsExistingFolders() throws {
        try withTemporaryDirectory { root in
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("资料", isDirectory: true),
                withIntermediateDirectories: false
            )
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("资料 2", isDirectory: true),
                withIntermediateDirectories: false
            )

            let destination = ArchiveExtractionDestination.unique(
                below: root,
                preferredName: "资料"
            )

            #expect(destination == root.appendingPathComponent("资料 3", isDirectory: true))
        }
    }

    @Test("direct extraction always targets the archive containing directory")
    func directExtractionUsesArchiveDirectory() throws {
        try withTemporaryDirectory { root in
            let archiveDirectory = root.appendingPathComponent("归档位置", isDirectory: true)
            let selectedDirectory = root.appendingPathComponent("其他位置", isDirectory: true)
            try FileManager.default.createDirectory(
                at: archiveDirectory,
                withIntermediateDirectories: false
            )
            try FileManager.default.createDirectory(
                at: selectedDirectory,
                withIntermediateDirectories: false
            )
            let archive = archiveDirectory.appendingPathComponent("资料.zip")

            let destination = ArchiveExtractionDestination.resolve(
                archiveURL: archive,
                selectedParent: selectedDirectory,
                createsIndependentFolder: false
            )

            #expect(destination == archiveDirectory)
        }
    }

    private func withTemporaryDirectory(
        _ body: (URL) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "aulycZip-extraction-destination-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }
}
