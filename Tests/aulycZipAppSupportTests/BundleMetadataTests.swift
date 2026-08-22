import Foundation
import Testing

@Suite("macOS bundle metadata")
struct BundleMetadataTests {
    @Test("Finder create and extract services declare their supported file types")
    func finderServiceDeclarations() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let plistData = try Data(contentsOf: root.appendingPathComponent("Config/Info.plist"))
        let plist = try #require(
            PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        )
        let services = try #require(plist["NSServices"] as? [[String: Any]])
        let createService = try #require(
            services.first { $0["NSMessage"] as? String == "createEncryptedZip" }
        )
        let createMenu = try #require(createService["NSMenuItem"] as? [String: String])
        let createContext = try #require(createService["NSRequiredContext"] as? [String: Any])
        let extractService = try #require(
            services.first { $0["NSMessage"] as? String == "extractZip" }
        )
        let extractMenu = try #require(extractService["NSMenuItem"] as? [String: String])
        let extractContext = try #require(extractService["NSRequiredContext"] as? [String: Any])

        #expect(services.count == 2)
        #expect(createMenu["default"] == "使用 aulycZip 加密压缩")
        #expect(createService["NSPortName"] as? String == "aulycZip")
        #expect(createService["NSSendFileTypes"] as? [String] == ["public.item"])
        #expect(createService["NSRestricted"] == nil)
        #expect(createContext["NSApplicationIdentifier"] as? String == "com.apple.finder")
        #expect(extractMenu["default"] == "使用 aulycZip 解压")
        #expect(extractService["NSPortName"] as? String == "aulycZip")
        #expect(extractService["NSSendFileTypes"] as? [String] == ["public.zip-archive"])
        #expect(extractService["NSRestricted"] == nil)
        #expect(extractContext["NSApplicationIdentifier"] as? String == "com.apple.finder")
    }
}
