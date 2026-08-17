import Foundation
import Testing

@Suite("macOS bundle metadata")
struct BundleMetadataTests {
    @Test("Finder encrypted ZIP service is declared without restricted-service confirmation")
    func finderServiceDeclaration() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let plistData = try Data(contentsOf: root.appendingPathComponent("Config/Info.plist"))
        let plist = try #require(
            PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        )
        let services = try #require(plist["NSServices"] as? [[String: Any]])
        let service = try #require(services.first)
        let menu = try #require(service["NSMenuItem"] as? [String: String])
        let context = try #require(service["NSRequiredContext"] as? [String: Any])

        #expect(services.count == 1)
        #expect(menu["default"] == "使用 aulycZip 加密压缩")
        #expect(service["NSMessage"] as? String == "createEncryptedZip")
        #expect(service["NSPortName"] as? String == "aulycZip")
        #expect(service["NSSendFileTypes"] as? [String] == ["public.item"])
        #expect(service["NSRestricted"] == nil)
        #expect(context["NSApplicationIdentifier"] as? String == "com.apple.finder")
    }
}
