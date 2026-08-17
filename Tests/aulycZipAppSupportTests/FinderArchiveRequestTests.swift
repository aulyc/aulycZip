import Foundation
import Testing
@testable import aulycZipAppSupport

@Suite("Finder encrypted archive request")
struct FinderArchiveRequestTests {
    @Test("one selected file creates a sibling encrypted ZIP name")
    func singleFileDestination() throws {
        try withFinderFixture { fixture in
            let source = fixture.root.appendingPathComponent("报告.pdf")
            try Data("content".utf8).write(to: source)

            let request = try FinderArchiveRequest(sourceURLs: [source])

            #expect(request.sourceURLs == [source.standardizedFileURL])
            #expect(request.destinationURL == fixture.root.appendingPathComponent("报告 加密.zip"))
            #expect(request.selectionSummary == "报告.pdf")
            #expect(request.targetSummary == source.standardizedFileURL.path)
        }
    }

    @Test("a different save directory keeps automatic naming and collision protection")
    func customDestinationDirectory() throws {
        try withFinderFixture { fixture in
            let source = fixture.root.appendingPathComponent("报告.pdf")
            let otherDirectory = fixture.root.appendingPathComponent("导出", isDirectory: true)
            try Data().write(to: source)
            try FileManager.default.createDirectory(at: otherDirectory, withIntermediateDirectories: true)
            try Data().write(to: otherDirectory.appendingPathComponent("报告 加密.zip"))

            let request = try FinderArchiveRequest(
                sourceURLs: [source],
                destinationDirectoryURL: otherDirectory
            )

            #expect(request.destinationURL == otherDirectory.appendingPathComponent("报告 加密 2.zip"))
        }
    }

    @Test("the source directory is available for the confirmation prompt")
    func sourceDirectorySummary() throws {
        try withFinderFixture { fixture in
            let source = fixture.root.appendingPathComponent("报告.pdf")
            try Data().write(to: source)

            let request = try FinderArchiveRequest(sourceURLs: [source])

            #expect(request.sourceDirectorySummary == fixture.root.path)
        }
    }

    @Test("source files from different folders show every involved directory")
    func multipleSourceDirectorySummary() throws {
        try withFinderFixture { fixture in
            let firstDirectory = fixture.root.appendingPathComponent("甲", isDirectory: true)
            let secondDirectory = fixture.root.appendingPathComponent("乙", isDirectory: true)
            try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
            let first = firstDirectory.appendingPathComponent("a.txt")
            let second = secondDirectory.appendingPathComponent("b.txt")
            try Data().write(to: first)
            try Data().write(to: second)

            let request = try FinderArchiveRequest(sourceURLs: [first, second])

            #expect(request.sourceDirectorySummary == "\(firstDirectory.path)、\(secondDirectory.path)")
        }
    }

    @Test("an editable output name gains the ZIP extension and never overwrites")
    func customOutputFileName() throws {
        try withFinderFixture { fixture in
            let source = fixture.root.appendingPathComponent("报告.pdf")
            try Data().write(to: source)
            try Data().write(to: fixture.root.appendingPathComponent("客户资料.zip"))

            let request = try FinderArchiveRequest(
                sourceURLs: [source],
                outputFileName: "客户资料"
            )

            #expect(request.destinationURL == fixture.root.appendingPathComponent("客户资料 2.zip"))
        }
    }

    @Test("an editable output name with ZIP already present does not duplicate the extension")
    func customOutputFileNameKeepsSingleZIPExtension() throws {
        try withFinderFixture { fixture in
            let source = fixture.root.appendingPathComponent("报告.pdf")
            try Data().write(to: source)

            let request = try FinderArchiveRequest(
                sourceURLs: [source],
                outputFileName: "客户资料.zip"
            )

            #expect(request.destinationURL == fixture.root.appendingPathComponent("客户资料.zip"))
        }
    }

    @Test("an output name cannot escape the selected save directory")
    func rejectsUnsafeOutputFileName() throws {
        try withFinderFixture { fixture in
            let source = fixture.root.appendingPathComponent("报告.pdf")
            try Data().write(to: source)

            #expect(throws: FinderArchiveRequestError.invalidOutputFileName) {
                _ = try FinderArchiveRequest(
                    sourceURLs: [source],
                    outputFileName: "../其他目录/资料.zip"
                )
            }
        }
    }

    @Test("many selected names are summarized without hiding the item count")
    func multipleSelectionSummary() throws {
        try withFinderFixture { fixture in
            let sources = ["a.txt", "b.txt", "c.txt", "d.txt"].map {
                fixture.root.appendingPathComponent($0)
            }
            for source in sources {
                try Data().write(to: source)
            }

            let request = try FinderArchiveRequest(sourceURLs: sources)

            #expect(request.selectionSummary == "a.txt、b.txt 等 4 项")
            #expect(request.targetSummary == "\(sources[0].path)、\(sources[1].path) 等 4 项")
        }
    }

    @Test("a file cannot be used as the save directory")
    func rejectsInvalidDestinationDirectory() throws {
        try withFinderFixture { fixture in
            let source = fixture.root.appendingPathComponent("source.txt")
            let notDirectory = fixture.root.appendingPathComponent("not-a-directory")
            try Data().write(to: source)
            try Data().write(to: notDirectory)

            #expect(throws: FinderArchiveRequestError.invalidDestinationDirectory) {
                _ = try FinderArchiveRequest(
                    sourceURLs: [source],
                    destinationDirectoryURL: notDirectory
                )
            }
        }
    }

    @Test("one selected folder preserves dotted folder names")
    func dottedFolderDestination() throws {
        try withFinderFixture { fixture in
            let source = fixture.root.appendingPathComponent("资料.2026", isDirectory: true)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

            let request = try FinderArchiveRequest(sourceURLs: [source])

            #expect(request.destinationURL == fixture.root.appendingPathComponent("资料.2026 加密.zip"))
        }
    }

    @Test("multiple selections use one archive beside the first item")
    func multipleSelectionDestination() throws {
        try withFinderFixture { fixture in
            let first = fixture.root.appendingPathComponent("a.txt")
            let second = fixture.root.appendingPathComponent("b.txt")
            try Data().write(to: first)
            try Data().write(to: second)

            let request = try FinderArchiveRequest(sourceURLs: [first, second])

            #expect(request.destinationURL == fixture.root.appendingPathComponent("加密归档.zip"))
        }
    }

    @Test("an existing destination receives a non-overwriting numeric suffix")
    func avoidsExistingDestination() throws {
        try withFinderFixture { fixture in
            let source = fixture.root.appendingPathComponent("报告.pdf")
            try Data().write(to: source)
            try Data().write(to: fixture.root.appendingPathComponent("报告 加密.zip"))
            try Data().write(to: fixture.root.appendingPathComponent("报告 加密 2.zip"))

            let request = try FinderArchiveRequest(sourceURLs: [source])

            #expect(request.destinationURL == fixture.root.appendingPathComponent("报告 加密 3.zip"))
        }
    }

    @Test("duplicate file URLs are collapsed in their original order")
    func removesDuplicateSources() throws {
        try withFinderFixture { fixture in
            let first = fixture.root.appendingPathComponent("a.txt")
            let second = fixture.root.appendingPathComponent("b.txt")
            try Data().write(to: first)
            try Data().write(to: second)

            let request = try FinderArchiveRequest(sourceURLs: [first, second, first])

            #expect(request.sourceURLs == [first.standardizedFileURL, second.standardizedFileURL])
        }
    }

    @Test("empty or non-file selections are rejected")
    func rejectsInvalidSelections() throws {
        #expect(throws: FinderArchiveRequestError.noUsableFiles) {
            _ = try FinderArchiveRequest(sourceURLs: [])
        }
        #expect(throws: FinderArchiveRequestError.noUsableFiles) {
            _ = try FinderArchiveRequest(sourceURLs: [URL(string: "https://example.com/file")!])
        }
    }
}

private struct FinderFixture {
    let root: URL
}

private func withFinderFixture(_ body: (FinderFixture) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aulycZip-finder-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(FinderFixture(root: root))
}
