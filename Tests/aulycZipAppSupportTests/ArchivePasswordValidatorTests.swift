import Testing
@testable import aulycZipAppSupport

@Suite("New archive password validation")
struct ArchivePasswordValidatorTests {
    @Test("passwords shorter than eight characters are rejected")
    func rejectsShortPassword() {
        let failure = ArchivePasswordValidator.validateNewPassword(
            "1234567",
            confirmation: "1234567"
        )
        #expect(failure == .tooShort)
        #expect(failure?.message == "密码至少需要 8 个字符。")
    }

    @Test("different confirmation is rejected")
    func rejectsMismatchedConfirmation() {
        let failure = ArchivePasswordValidator.validateNewPassword(
            "12345678",
            confirmation: "87654321"
        )
        #expect(failure == .confirmationMismatch)
        #expect(failure?.message == "两次输入的密码不一致。")
    }

    @Test("matching eight-character password is accepted")
    func acceptsMinimumLengthPassword() {
        #expect(
            ArchivePasswordValidator.validateNewPassword(
                "12345678",
                confirmation: "12345678"
            ) == nil
        )
    }
}
