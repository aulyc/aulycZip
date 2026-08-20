import AppKit
import aulycZipAppSupport

@MainActor
struct ArchiveActionValidation {
    let title: String
    let message: String
    let buttonTitle: String
    let firstResponder: NSView?
}

@MainActor
final class ArchiveActionDialog: NSObject {
    private let panel: NSPanel
    private weak var initialFirstResponder: NSView?
    private let validationHandler: () -> ArchiveActionValidation?

    init(
        accessoryView: NSView,
        supplementaryButton: NSButton? = nil,
        primaryButtonTitle: String,
        initialFirstResponder: NSView? = nil,
        validationHandler: @escaping () -> ArchiveActionValidation?
    ) {
        self.initialFirstResponder = initialFirstResponder
        self.validationHandler = validationHandler

        let accessorySize = accessoryView.frame.size
        let contentSize = NSSize(
            width: accessorySize.width + 40,
            height: accessorySize.height + 88
        )
        panel = AppModalPanel.make(size: contentSize)
        super.init()

        let cancelButton = NSButton(
            title: "取消",
            target: self,
            action: #selector(cancel(_:))
        )
        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .large
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.setAccessibilityIdentifier("action-button-2")

        let primaryButton = NSButton(
            title: primaryButtonTitle,
            target: self,
            action: #selector(submit(_:))
        )
        primaryButton.bezelStyle = .rounded
        primaryButton.controlSize = .large
        primaryButton.keyEquivalent = "\r"
        primaryButton.setAccessibilityIdentifier("action-button-1")

        supplementaryButton?.bezelStyle = .rounded
        supplementaryButton?.controlSize = .large

        var actionButtons = [cancelButton]
        if let supplementaryButton {
            actionButtons.append(supplementaryButton)
        }
        actionButtons.append(primaryButton)
        let buttons = NSStackView(views: actionButtons)
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        guard let contentView = panel.contentView else { return }
        accessoryView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(accessoryView)
        contentView.addSubview(buttons)
        NSLayoutConstraint.activate([
            accessoryView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            accessoryView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            accessoryView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            accessoryView.heightAnchor.constraint(equalToConstant: accessorySize.height),
            buttons.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            buttons.topAnchor.constraint(equalTo: accessoryView.bottomAnchor, constant: 14),
            buttons.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ] + actionButtons.flatMap { button in
            [
                button.widthAnchor.constraint(equalToConstant: 110),
                button.heightAnchor.constraint(equalToConstant: 32),
            ]
        })
        panel.defaultButtonCell = primaryButton.cell as? NSButtonCell
    }

    func runModal() -> NSApplication.ModalResponse {
        AppModalPanel.run(panel) { [weak self] in
            guard let self,
                  let initialFirstResponder = self.initialFirstResponder
            else { return }
            if let passwordEntry = initialFirstResponder as? PasswordEntryControl {
                passwordEntry.focus()
            } else {
                panel.makeFirstResponder(initialFirstResponder)
            }
        }
    }

    @objc private func submit(_ sender: NSButton) {
        if let validation = validationHandler() {
            showValidation(validation)
            return
        }
        NSApp.stopModal(withCode: .alertFirstButtonReturn)
    }

    @objc private func cancel(_ sender: NSButton) {
        NSApp.stopModal(withCode: .alertSecondButtonReturn)
    }

    private func showValidation(_ validation: ArchiveActionValidation) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = validation.title
        alert.informativeText = validation.message
        alert.addButton(withTitle: validation.buttonTitle)
        alert.beginSheetModal(for: panel) { [weak self] _ in
            guard let self else { return }
            panel.makeKeyAndOrderFront(nil)
            if let passwordEntry = validation.firstResponder as? PasswordEntryControl {
                passwordEntry.focus()
            } else if let firstResponder = validation.firstResponder {
                panel.makeFirstResponder(firstResponder)
            }
        }
    }
}

@MainActor
final class EncryptedArchiveLocationController: NSObject {
    private(set) var request: EncryptedArchiveRequest
    private var passwordGenerationController: GeneratedPasswordController?
    let outputFileControl: ArchiveFileNameControl

    init(request: EncryptedArchiveRequest, outputFileName: String) {
        self.request = request
        outputFileControl = ArchiveFileNameControl(
            baseName: outputFileName.isEmpty
                ? request.destinationURL.deletingPathExtension().lastPathComponent
                : outputFileName
        )
        super.init()
        refreshLabels()
    }

    func makeOutputFileControl() -> NSView {
        let chooseButton = NSButton(
            image: NSImage(
                systemSymbolName: "folder",
                accessibilityDescription: "选择保存位置"
            ) ?? NSImage(),
            target: self,
            action: #selector(chooseDestinationDirectory(_:))
        )
        chooseButton.bezelStyle = .rounded
        chooseButton.controlSize = .regular
        chooseButton.imagePosition = .imageOnly
        chooseButton.imageScaling = .scaleProportionallyDown
        chooseButton.contentTintColor = .secondaryLabelColor
        chooseButton.toolTip = "选择加密 ZIP 的保存目录"
        chooseButton.setAccessibilityLabel("选择保存位置")
        chooseButton.setAccessibilityIdentifier("archive-output-directory-picker")

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        outputFileControl.translatesAutoresizingMaskIntoConstraints = false
        chooseButton.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(outputFileControl)
        row.addSubview(chooseButton)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 28),
            outputFileControl.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            outputFileControl.trailingAnchor.constraint(equalTo: chooseButton.leadingAnchor, constant: -8),
            outputFileControl.topAnchor.constraint(equalTo: row.topAnchor),
            outputFileControl.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            chooseButton.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            chooseButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            chooseButton.widthAnchor.constraint(equalToConstant: 28),
            chooseButton.heightAnchor.constraint(equalToConstant: 28),
        ])
        return row
    }

    func makePasswordGeneratorButton(
        passwordField: PasswordEntryControl,
        confirmationField: PasswordEntryControl
    ) -> NSButton {
        let controller = GeneratedPasswordController(
            passwordField: passwordField,
            confirmationField: confirmationField
        )
        passwordGenerationController = controller

        let button = NSButton(
            title: "随机密码填充",
            target: controller,
            action: #selector(GeneratedPasswordController.generatePassword(_:))
        )
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.setAccessibilityIdentifier("archive-password-generator")
        return button
    }

    @objc private func chooseDestinationDirectory(_ sender: NSButton) {
        guard let parentWindow = sender.window else { return }

        let panel = NSOpenPanel()
        panel.title = "选择加密 ZIP 保存目录"
        panel.prompt = "选择此目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = request.destinationURL.deletingLastPathComponent()
        panel.beginSheetModal(for: parentWindow) { [weak self] response in
            guard response == .OK, let directory = panel.url, let self else { return }

            do {
                let preservedName = request.destinationURL
                    .deletingPathExtension()
                    .lastPathComponent
                request = try EncryptedArchiveRequest(
                    sourceURLs: request.sourceURLs,
                    destinationDirectoryURL: directory,
                    outputFileName: preservedName
                )
                refreshLabels()
            } catch {
                showDirectorySelectionFailure(on: parentWindow)
            }
        }
    }

    private func showDirectorySelectionFailure(on window: NSWindow) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "无法使用这个保存位置"
        alert.informativeText = "请选择一个仍然存在且可以访问的文件夹。"
        alert.addButton(withTitle: "好")
        alert.beginSheetModal(for: window)
    }

    private func refreshLabels() {
        let directory = request.destinationURL.deletingLastPathComponent()
        outputFileControl.directoryPath = directory.path
    }
}
