import AppKit
import aulycZipAppSupport

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let onCreateEncrypted: () -> Void
    private let onExtract: () -> Void
    private let onShowHelp: () -> Void
    private let onShowAbout: () -> Void
    private let onCheckForUpdates: () -> Void

    init(
        onCreateEncrypted: @escaping () -> Void,
        onExtract: @escaping () -> Void,
        onShowHelp: @escaping () -> Void,
        onShowAbout: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void
    ) {
        self.onCreateEncrypted = onCreateEncrypted
        self.onExtract = onExtract
        self.onShowHelp = onShowHelp
        self.onShowAbout = onShowAbout
        self.onCheckForUpdates = onCheckForUpdates
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = Self.statusBarIcon()
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.setAccessibilityLabel("aulycZip")
            button.setAccessibilityIdentifier("aulyczip-status-bar-button")
        }
        setupMenu()
    }

    private func setupMenu() {
        let menu = NSMenu()
        for action in StatusMenuAction.primary {
            let selector: Selector
            switch action {
            case .createEncrypted: selector = #selector(createEncrypted)
            case .extract: selector = #selector(extract)
            }
            menu.addItem(item(
                title: action.title,
                action: selector,
                systemImage: action.systemImage
            ))
        }
        menu.addItem(.separator())
        menu.addItem(item(
            title: "使用说明",
            action: #selector(showHelp),
            systemImage: "questionmark.circle"
        ))
        menu.addItem(item(
            title: "关于 aulycZip",
            action: #selector(showAbout),
            systemImage: "info.circle"
        ))
        menu.addItem(item(
            title: "检查更新…",
            action: #selector(checkForUpdates),
            systemImage: "arrow.triangle.2.circlepath"
        ))
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "退出 aulycZip",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.image = Self.menuIcon(systemName: "power")
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func item(title: String, action: Selector, systemImage: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = Self.menuIcon(systemName: systemImage)
        return item
    }

    private static func menuIcon(systemName: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        return image
    }

    private static func statusBarIcon() -> NSImage {
        let size = NSSize(width: 20, height: 20)
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            image.size = size
            image.isTemplate = true
            return image
        }
        if Bundle.main.bundleIdentifier == nil,
           let url = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            image.size = size
            image.isTemplate = true
            return image
        }

        let fallback = NSImage(systemSymbolName: "archivebox", accessibilityDescription: "aulycZip")
            ?? NSImage(size: size)
        fallback.size = size
        fallback.isTemplate = true
        return fallback
    }

    @objc private func createEncrypted() { onCreateEncrypted() }
    @objc private func extract() { onExtract() }
    @objc private func showHelp() { onShowHelp() }
    @objc private func showAbout() { onShowAbout() }
    @objc private func checkForUpdates() { onCheckForUpdates() }
}
