import AppKit
import aulycZipAppSupport

@MainActor
final class GeneratedPasswordController: NSObject {
    private let passwordField: PasswordEntryControl
    private let confirmationField: PasswordEntryControl

    init(passwordField: PasswordEntryControl, confirmationField: PasswordEntryControl) {
        self.passwordField = passwordField
        self.confirmationField = confirmationField
    }

    @objc func generatePassword(_ sender: NSButton) {
        let parentWindow = sender.window
        let generatedPassword: String
        do {
            generatedPassword = try ArchivePasswordGenerator.generate()
        } catch {
            showGenerationFailure()
            return
        }

        let dialog = GeneratedPasswordDialog(password: generatedPassword)
        let choice = dialog.runModal(relativeTo: parentWindow)

        NSApp.activate(ignoringOtherApps: true)
        parentWindow?.makeKeyAndOrderFront(nil)

        guard choice.confirmed else { return }

        passwordField.stringValue = generatedPassword
        confirmationField.stringValue = generatedPassword
        if choice.copyToPasteboard {
            PasswordPasteboardWriter.write(generatedPassword)
        }
    }

    private func showGenerationFailure() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "无法生成安全密码"
        alert.informativeText = "系统安全随机源暂时不可用，请稍后重试或手动输入密码。"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

@MainActor
final class GeneratedPasswordDialog: NSObject {
    struct Choice {
        let confirmed: Bool
        let copyToPasteboard: Bool
    }

    private let panel: NSPanel
    private let copyCheckbox: NSButton

    init(password: String) {
        panel = AppModalPanel.make(size: NSSize(width: 380, height: 210))
        copyCheckbox = NSButton(
            checkboxWithTitle: "确定后复制密码到剪贴板",
            target: nil,
            action: nil
        )
        super.init()

        let header = appDialogHeader(
            title: "请保存好自动生成的密码",
            accessibilityIdentifier: "generated-password-title"
        )

        let message = NSTextField(
            labelWithString: "aulycZip 不会保存密码，忘记后无法恢复。"
        )
        message.font = .systemFont(ofSize: 13)
        message.textColor = .secondaryLabelColor
        message.maximumNumberOfLines = 1
        message.lineBreakMode = .byTruncatingTail

        let generatedField = NSTextField(string: password)
        generatedField.isEditable = false
        generatedField.isSelectable = true
        generatedField.isBezeled = true
        generatedField.drawsBackground = true
        generatedField.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        generatedField.alignment = .center
        generatedField.setAccessibilityLabel("自动生成的 16 位密码")
        generatedField.setAccessibilityIdentifier("generated-archive-password")

        copyCheckbox.state = .on
        copyCheckbox.setAccessibilityIdentifier("copy-generated-password")

        let cancelButton = NSButton(
            title: "取消",
            target: self,
            action: #selector(cancel(_:))
        )
        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .large
        cancelButton.keyEquivalent = "\u{1b}"

        let confirmButton = NSButton(
            title: "确定",
            target: self,
            action: #selector(confirm(_:))
        )
        confirmButton.bezelStyle = .rounded
        confirmButton.controlSize = .large
        confirmButton.keyEquivalent = "\r"

        let buttons = NSStackView(views: [cancelButton, confirmButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let buttonContainer = NSView()
        buttonContainer.translatesAutoresizingMaskIntoConstraints = false
        buttonContainer.addSubview(buttons)
        NSLayoutConstraint.activate([
            buttons.centerXAnchor.constraint(equalTo: buttonContainer.centerXAnchor),
            buttons.topAnchor.constraint(equalTo: buttonContainer.topAnchor),
            buttons.bottomAnchor.constraint(equalTo: buttonContainer.bottomAnchor),
        ])

        let stack = NSStackView(views: [
            header,
            message,
            generatedField,
            copyCheckbox,
            buttonContainer,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(14, after: header)
        stack.setCustomSpacing(18, after: copyCheckbox)
        stack.translatesAutoresizingMaskIntoConstraints = false

        guard let contentView = panel.contentView else { return }
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            header.widthAnchor.constraint(equalToConstant: 340),
            message.widthAnchor.constraint(equalToConstant: 340),
            generatedField.widthAnchor.constraint(equalToConstant: 340),
            generatedField.heightAnchor.constraint(equalToConstant: 28),
            buttonContainer.widthAnchor.constraint(equalToConstant: 340),
            cancelButton.widthAnchor.constraint(equalToConstant: 110),
            confirmButton.widthAnchor.constraint(equalToConstant: 110),
            cancelButton.heightAnchor.constraint(equalToConstant: 32),
            confirmButton.heightAnchor.constraint(equalToConstant: 32),
        ])
        panel.defaultButtonCell = confirmButton.cell as? NSButtonCell
    }

    func runModal(relativeTo parentWindow: NSWindow?) -> Choice {
        let response = AppModalPanel.run(panel, relativeTo: parentWindow)
        return Choice(
            confirmed: response == .alertFirstButtonReturn,
            copyToPasteboard: copyCheckbox.state == .on
        )
    }

    @objc private func confirm(_ sender: NSButton) {
        NSApp.stopModal(withCode: .alertFirstButtonReturn)
    }

    @objc private func cancel(_ sender: NSButton) {
        NSApp.stopModal(withCode: .alertSecondButtonReturn)
    }
}
