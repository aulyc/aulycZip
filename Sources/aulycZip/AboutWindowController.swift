import AppKit

private final class AboutWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if flags == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class AboutWindowController: NSObject {
    private static let websiteURL = URL(string: "https://www.aulyc.com")!
    private var aboutWindow: AboutWindow?

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let aboutWindow {
            aboutWindow.center()
            aboutWindow.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = makeContentView()
        let window = AboutWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "关于 aulycZip"
        window.titleVisibility = .visible
        window.contentView = contentView
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 500, height: 500))
        window.contentMinSize = NSSize(width: 500, height: 500)
        window.contentMaxSize = NSSize(width: 500, height: 500)
        aboutWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeContentView() -> NSView {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "开发版"
        let minimumSystemVersion = Bundle.main.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String
            ?? "14.0"
        let majorSystemVersion = minimumSystemVersion.split(separator: ".").first.map(String.init)
            ?? minimumSystemVersion

        let metadata = NSGridView(views: [
            metadataRow(title: "应用版本", value: version),
            metadataRow(title: "适配芯片", value: "Apple Silicon"),
            metadataRow(title: "系统要求", value: "macOS \(majorSystemVersion)+"),
        ])
        metadata.rowSpacing = 6
        metadata.columnSpacing = 12
        metadata.column(at: 0).xPlacement = .leading
        metadata.column(at: 1).xPlacement = .leading
        for rowIndex in 0..<metadata.numberOfRows {
            metadata.row(at: rowIndex).yPlacement = .center
        }

        let introduction = section(title: "应用介绍", views: [
            bodyLabel("1. aulycZip 是一款原生 macOS 菜单栏加密 ZIP 工具，可从菜单栏或 Finder 右键创建 WinZip AES-256 加密 ZIP；"),
            bodyLabel("2. 应用可以解压普通 ZIP 和 WinZip AES-128/192/256 加密 ZIP，并在写出文件前验证密码和认证码；"),
            bodyLabel("3. 密码仅用于当前操作，不会保存或写入日志；ZIP 文件名和目录名不会被加密，仍可能被其他软件看到。"),
        ])

        let websiteButton = NSButton(
            title: Self.websiteURL.absoluteString,
            target: self,
            action: #selector(openOfficialWebsite)
        )
        websiteButton.isBordered = false
        websiteButton.font = .systemFont(ofSize: 13)
        websiteButton.contentTintColor = .linkColor
        websiteButton.alignment = .left
        websiteButton.toolTip = "使用默认浏览器打开官方网站"
        websiteButton.setAccessibilityLabel("官方网站：\(Self.websiteURL.absoluteString)")
        let website = section(title: "官方网站", views: [websiteButton])

        let acknowledgements = section(title: "致谢", views: [
            bodyLabel("1. 感谢 Apple 提供 Swift、AppKit、CommonCrypto 与 Compression 等系统能力；"),
            bodyLabel("2. 感谢伟大的 AI 时代；"),
            bodyLabel("3. 致敬 Codex & Claude；"),
            bodyLabel("4. 感谢 WinZip AES 格式规范，以及 7-Zip 与 Keka 提供的兼容性参考；"),
            bodyLabel("5. 感谢 aulyc 带来的坚持和灵感。"),
        ])

        let copyright = NSTextField(labelWithString: "Copyright © 2026 aulyc. All rights reserved.")
        copyright.font = .systemFont(ofSize: 11)
        copyright.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [metadata, introduction, website, acknowledgements, copyright])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
        ])
        return contentView
    }

    private func metadataRow(title: String, value: String) -> [NSView] {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.widthAnchor.constraint(equalToConstant: 58).isActive = true

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = .systemFont(ofSize: 13)
        valueLabel.textColor = .secondaryLabelColor
        return [titleLabel, valueLabel]
    }

    private func section(title: String, views: [NSView]) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        let stack = NSStackView(views: [titleLabel] + views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        return stack
    }

    private func bodyLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.widthAnchor.constraint(equalToConstant: 456).isActive = true
        return label
    }

    @objc private func openOfficialWebsite() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(Self.websiteURL, configuration: configuration) { [weak self] _, error in
            guard let error else { return }
            Task { @MainActor [weak self] in
                self?.showWebsiteOpenFailure(error: error)
            }
        }
    }

    private func showWebsiteOpenFailure(error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "无法打开官方网站"
        alert.informativeText = """
        请确认已设置可用的默认浏览器后重试。

        \(Self.websiteURL.absoluteString)

        \(error.localizedDescription)
        """
        alert.addButton(withTitle: "好")
        if let aboutWindow, aboutWindow.isVisible {
            alert.beginSheetModal(for: aboutWindow)
        } else {
            alert.runModal()
        }
    }
}
