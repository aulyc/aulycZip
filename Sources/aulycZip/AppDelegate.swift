import AppKit
import aulycZipAppSupport

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var workflowController: ArchiveWorkflowController?
    private var finderServiceProvider: FinderServiceProvider?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let workflow = ArchiveWorkflowController()
        workflowController = workflow
        statusBarController = StatusBarController(
            onCreateEncrypted: { [weak workflow] in workflow?.createEncryptedArchive() },
            onExtract: { [weak workflow] in workflow?.extractArchive() },
            onShowHelp: { [weak workflow] in workflow?.showHelp() },
            onShowAbout: { [weak workflow] in workflow?.showAbout() }
        )

        let serviceProvider = FinderServiceProvider { [weak workflow] urls in
            Task { @MainActor [weak workflow] in
                workflow?.createEncryptedArchiveFromFinder(urls)
            }
        }
        finderServiceProvider = serviceProvider
        NSApp.servicesProvider = serviceProvider
        NSUpdateDynamicServices()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
