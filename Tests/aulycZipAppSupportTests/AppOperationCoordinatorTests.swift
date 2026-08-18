import Testing
@testable import aulycZipAppSupport

@MainActor
@Suite("App operation coordination")
struct AppOperationCoordinatorTests {
    @Test("archive and update replacement are mutually exclusive")
    func exclusiveOperations() {
        let coordinator = AppOperationCoordinator()

        #expect(coordinator.begin(.archive))
        #expect(!coordinator.begin(.updateReplacement))
        coordinator.end(.archive)
        #expect(coordinator.begin(.updateReplacement))
        #expect(!coordinator.begin(.archive))
        coordinator.end(.updateReplacement)
        #expect(coordinator.activeOperation == nil)
    }

    @Test("ending a stale operation cannot release the active owner")
    func ownership() {
        let coordinator = AppOperationCoordinator()
        #expect(coordinator.begin(.archive))
        coordinator.end(.updateReplacement)
        #expect(coordinator.activeOperation == .archive)
    }
}
