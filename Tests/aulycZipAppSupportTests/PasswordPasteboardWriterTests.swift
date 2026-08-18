import AppKit
import Testing
@testable import aulycZipAppSupport

@Suite("Password pasteboard privacy")
struct PasswordPasteboardWriterTests {
    @Test("copied passwords carry concealed and transient markers")
    func privacyMarkers() throws {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("aulycZip.password-tests.\(UUID().uuidString)")
        )
        #expect(PasswordPasteboardWriter.write("one-time-secret", to: pasteboard))
        let item = try #require(pasteboard.pasteboardItems?.first)

        #expect(item.string(forType: .string) == "one-time-secret")
        #expect(item.types.contains(PasswordPasteboardWriter.concealedType))
        #expect(item.types.contains(PasswordPasteboardWriter.transientType))
    }
}
