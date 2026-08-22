import AppKit
import Foundation
import Testing
@testable import aulycZipAppSupport

@Suite("Finder service provider")
@MainActor
struct FinderServiceProviderTests {
    @Test("file URLs from the service pasteboard are delivered to the app")
    func deliversFileURLs() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("aulycZip-service-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("文件.txt")
        try Data().write(to: source)

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("aulycZip.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects([source as NSURL]))

        var delivered: [URL] = []
        var extracted: URL?
        let provider = FinderServiceProvider(
            onCreateSelection: { delivered = $0 },
            onExtractSelection: { extracted = $0 }
        )
        #expect(provider.responds(to: NSSelectorFromString("createEncryptedZip:userData:error:")))
        var serviceError: NSString?
        provider.createEncryptedZip(pasteboard, userData: nil, error: &serviceError)

        #expect(delivered == [source])
        #expect(extracted == nil)
        #expect(serviceError == nil)
    }

    @Test("one ZIP URL from the extraction service is delivered to the app")
    func deliversArchiveURLForExtraction() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("aulycZip-service-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("资料.ZIP")
        try Data().write(to: archive)

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("aulycZip.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects([archive as NSURL]))

        var created: [URL] = []
        var extracted: URL?
        let provider = FinderServiceProvider(
            onCreateSelection: { created = $0 },
            onExtractSelection: { extracted = $0 }
        )
        #expect(provider.responds(to: NSSelectorFromString("extractZip:userData:error:")))
        var serviceError: NSString?
        provider.extractZip(pasteboard, userData: nil, error: &serviceError)

        #expect(created.isEmpty)
        #expect(extracted == archive)
        #expect(serviceError == nil)
    }

    @Test("a service request without file URLs reports an error")
    func rejectsMissingFileURLs() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("aulycZip.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("not a file", forType: .string)

        var callbackCount = 0
        let provider = FinderServiceProvider(
            onCreateSelection: { _ in callbackCount += 1 },
            onExtractSelection: { _ in callbackCount += 1 }
        )
        var serviceError: NSString?
        provider.createEncryptedZip(pasteboard, userData: nil, error: &serviceError)

        #expect(callbackCount == 0)
        #expect(serviceError != nil)
    }

    @Test("the extraction service rejects a non-ZIP file")
    func rejectsNonArchiveExtraction() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("aulycZip-service-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("资料.txt")
        try Data().write(to: source)

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("aulycZip.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects([source as NSURL]))

        var callbackCount = 0
        let provider = FinderServiceProvider(
            onCreateSelection: { _ in callbackCount += 1 },
            onExtractSelection: { _ in callbackCount += 1 }
        )
        var serviceError: NSString?
        provider.extractZip(pasteboard, userData: nil, error: &serviceError)

        #expect(callbackCount == 0)
        #expect(serviceError == "Finder 没有提供可解压的 ZIP 文件")
    }

    @Test("the extraction service rejects multiple ZIP files")
    func rejectsMultipleArchives() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("aulycZip-service-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let archives = ["a.zip", "b.zip"].map { root.appendingPathComponent($0) }
        for archive in archives {
            try Data().write(to: archive)
        }

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("aulycZip.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects(archives.map { $0 as NSURL }))

        var callbackCount = 0
        let provider = FinderServiceProvider(
            onCreateSelection: { _ in callbackCount += 1 },
            onExtractSelection: { _ in callbackCount += 1 }
        )
        var serviceError: NSString?
        provider.extractZip(pasteboard, userData: nil, error: &serviceError)

        #expect(callbackCount == 0)
        #expect(serviceError == "请在 Finder 中只选择一个 ZIP 文件进行解压")
    }
}
