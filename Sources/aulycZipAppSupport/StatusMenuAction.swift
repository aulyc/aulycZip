public enum StatusMenuAction: Equatable, Sendable {
    case createEncrypted
    case extract

    public static let primary: [StatusMenuAction] = [
        .createEncrypted,
        .extract,
    ]

    public var title: String {
        switch self {
        case .createEncrypted: "创建加密 ZIP…"
        case .extract: "解压 ZIP…"
        }
    }

    public var systemImage: String {
        switch self {
        case .createEncrypted: "lock.fill"
        case .extract: "archivebox.badge.plus"
        }
    }
}
