import AppKit
import aulycZipAppSupport

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var workflowController: ArchiveWorkflowController?
    private var finderServiceProvider: FinderServiceProvider?
    private var updateController: UpdateController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let operationCoordinator = AppOperationCoordinator()
        let workflow = ArchiveWorkflowController(operationCoordinator: operationCoordinator)
        let updater = UpdateController(operationCoordinator: operationCoordinator)
        workflowController = workflow
        updateController = updater
        statusBarController = StatusBarController(
            onCreateEncrypted: { [weak workflow] in workflow?.createEncryptedArchive() },
            onExtract: { [weak workflow] in workflow?.extractArchive() },
            onShowAbout: { [weak workflow] in workflow?.showAbout() },
            onCheckForUpdates: { [weak updater] in updater?.checkManually() }
        )

        let serviceProvider = FinderServiceProvider { [weak workflow] urls in
            Task { @MainActor [weak workflow] in
                workflow?.createEncryptedArchiveFromFinder(urls)
            }
        }
        finderServiceProvider = serviceProvider
        NSApp.servicesProvider = serviceProvider
        NSUpdateDynamicServices()
        updater.scheduleAutomaticCheckIfDue()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
