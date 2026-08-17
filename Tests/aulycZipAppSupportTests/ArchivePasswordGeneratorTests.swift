import Testing
@testable import aulycZipAppSupport

@Suite("Generated archive passwords")
struct ArchivePasswordGeneratorTests {
    @Test("the default password is 16 characters and covers every required category")
    func defaultPasswordShape() throws {
        let password = try ArchivePasswordGenerator.generate()

        #expect(password.count == 16)
        #expect(password.contains { ArchivePasswordGenerator.uppercaseCharacters.contains($0) })
        #expect(password.contains { ArchivePasswordGenerator.lowercaseCharacters.contains($0) })
        #expect(password.contains { ArchivePasswordGenerator.digitCharacters.contains($0) })
        #expect(password.contains { ArchivePasswordGenerator.symbolCharacters.contains($0) })
        #expect(password.allSatisfy { ArchivePasswordGenerator.allowedCharacters.contains($0) })
    }

    @Test("a password shorter than four characters is rejected")
    func rejectsTooShortLength() {
        #expect(throws: ArchivePasswordGeneratorError.lengthTooShort) {
            _ = try ArchivePasswordGenerator.generate(length: 3)
        }
    }
}
