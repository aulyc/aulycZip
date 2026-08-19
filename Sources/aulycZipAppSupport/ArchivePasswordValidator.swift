package enum ArchivePasswordValidationFailure: Equatable, Sendable {
    case tooShort
    case confirmationMismatch

    package var message: String {
        switch self {
        case .tooShort:
            "密码至少需要 8 个字符。"
        case .confirmationMismatch:
            "两次输入的密码不一致。"
        }
    }
}

package enum ArchivePasswordValidator {
    package static func validateNewPassword(
        _ password: String,
        confirmation: String
    ) -> ArchivePasswordValidationFailure? {
        guard password.count >= 8 else { return .tooShort }
        guard password == confirmation else { return .confirmationMismatch }
        return nil
    }
}
