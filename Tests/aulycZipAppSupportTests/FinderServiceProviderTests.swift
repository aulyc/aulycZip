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
        let provider = FinderServiceProvider { delivered = $0 }
        #expect(provider.responds(to: NSSelectorFromString("createEncryptedZip:userData:error:")))
        var serviceError: NSString?
        provider.createEncryptedZip(pasteboard, userData: nil, error: &serviceError)

        #expect(delivered == [source])
        #expect(serviceError == nil)
    }

    @Test("a service request without file URLs reports an error")
    func rejectsMissingFileURLs() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("aulycZip.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("not a file", forType: .string)

        var callbackCount = 0
        let provider = FinderServiceProvider { _ in callbackCount += 1 }
        var serviceError: NSString?
        provider.createEncryptedZip(pasteboard, userData: nil, error: &serviceError)

        #expect(callbackCount == 0)
        #expect(serviceError != nil)
    }
}
