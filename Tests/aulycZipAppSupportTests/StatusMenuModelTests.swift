import Testing
@testable import aulycZipAppSupport

@Suite("aulycZip status menu")
struct StatusMenuModelTests {
    @Test("the primary menu offers encrypted creation and extraction only")
    func primaryActionsExcludePlainCompression() {
        #expect(StatusMenuAction.primary.map(\.title) == ["创建加密 ZIP…", "解压 ZIP…"])
        #expect(StatusMenuAction.primary.map(\.systemImage) == ["lock.fill", "archivebox"])
        #expect(!StatusMenuAction.primary.map(\.title).contains("创建普通 ZIP…"))
    }
}
