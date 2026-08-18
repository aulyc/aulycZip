import Foundation

public enum AppExclusiveOperation: Equatable, Sendable {
    case archive
    case updateReplacement
}

@MainActor
public final class AppOperationCoordinator {
    public private(set) var activeOperation: AppExclusiveOperation?

    public init() {}

    @discardableResult
    public func begin(_ operation: AppExclusiveOperation) -> Bool {
        guard activeOperation == nil else { return false }
        activeOperation = operation
        return true
    }

    public func end(_ operation: AppExclusiveOperation) {
        guard activeOperation == operation else { return }
        activeOperation = nil
    }
}
