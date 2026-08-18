import AppKit
import aulycZipAppSupport

struct FinderArchiveCreationChoice: Sendable {
    let password: String
    let request: FinderArchiveRequest
}

@MainActor
enum PasswordPrompt {
    static func requestNewPassword() -> String? {
        while true {
            let first = secureTextField(placeholder: "至少 8 个字符")
            let confirmation = secureTextField(
                placeholder: "再次输入密码",
                visibilityIdentifier: "confirmation-password-visibility"
            )
            let accessory = passwordAccessory(rows: [
                ("密码", first),
                ("确认", confirmation),
            ])

            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "设置文件加密压缩密码"
            alert.informativeText = "使用 WinZip AES-256 加密文件内容；文件名仍然可见。密码不会保存，忘记后无法恢复。"
            alert.accessoryView = accessory
            alert.addButton(withTitle: "创建")
            alert.addButton(withTitle: "取消")
            alert.window.initialFirstResponder = first
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }

            if first.stringValue.count < 8 {
                showValidation(message: "密码至少需要 8 个字符。")
                continue
            }
            if first.stringValue != confirmation.stringValue {
                showValidation(message: "两次输入的密码不一致。")
                continue
            }
            return first.stringValue
        }
    }

    static func requestNewPassword(
        for initialRequest: FinderArchiveRequest
    ) -> FinderArchiveCreationChoice? {
        var currentRequest = initialRequest
        var pendingPassword = ""
        var pendingConfirmation = ""
        var pendingOutputFileName = initialRequest.destinationURL
            .deletingPathExtension()
            .lastPathComponent

        while true {
            let first = secureTextField(
                placeholder: "至少 8 个字符",
                value: pendingPassword,
                visibilityIdentifier: "archive-password-visibility"
            )
            let confirmation = secureTextField(
                placeholder: "再次输入密码",
                value: pendingConfirmation,
                visibilityIdentifier: "archive-confirmation-password-visibility"
            )
            let locationController = FinderArchiveLocationController(
                request: currentRequest,
                outputFileName: pendingOutputFileName
            )
            let randomPasswordButton = locationController.makePasswordGeneratorButton(
                passwordField: first,
                confirmationField: confirmation
            )
            let accessory = finderArchiveAccessory(
                locationController: locationController,
                sourceRequest: initialRequest,
                password: first,
                confirmation: confirmation
            )

            let dialog = FinderArchivePasswordDialog(
                accessoryView: accessory,
                randomPasswordButton: randomPasswordButton,
                initialFirstResponder: first,
                validationHandler: {
                    if first.stringValue.count < 8 {
                        return FinderArchivePasswordValidation(
                            title: "请检查密码",
                            message: "密码至少需要 8 个字符。",
                            buttonTitle: "重新输入",
                            firstResponder: first
                        )
                    }
                    if first.stringValue != confirmation.stringValue {
                        return FinderArchivePasswordValidation(
                            title: "请检查密码",
                            message: "两次输入的密码不一致。",
                            buttonTitle: "重新输入",
                            firstResponder: confirmation
                        )
                    }
                    guard let outputFileName = editableOutputFileName(
                        locationController.outputFileControl.baseName
                    ) else {
                        return FinderArchivePasswordValidation(
                            title: "无法使用这个输出文件名",
                            message: "请输入普通文件名，不要包含路径、斜杠、反斜杠或冒号。.zip 扩展名由应用固定添加。",
                            buttonTitle: "重新输入",
                            firstResponder: locationController.outputFileControl
                        )
                    }
                    do {
                        _ = try FinderArchiveRequest(
                            sourceURLs: locationController.request.sourceURLs,
                            destinationDirectoryURL: locationController.request.destinationURL
                                .deletingLastPathComponent(),
                            outputFileName: outputFileName
                        )
                    } catch {
                        return FinderArchivePasswordValidation(
                            title: "无法使用这个保存位置",
                            message: "请选择一个仍然存在且可以访问的文件夹。",
                            buttonTitle: "好",
                            firstResponder: nil
                        )
                    }
                    return nil
                }
            )
            let response = dialog.runModal()

            pendingPassword = first.stringValue
            pendingConfirmation = confirmation.stringValue
            pendingOutputFileName = locationController.outputFileControl.baseName
            currentRequest = locationController.request

            guard response == .alertFirstButtonReturn else { return nil }
            guard let outputFileName = editableOutputFileName(pendingOutputFileName) else {
                showArchiveRequestValidation(for: FinderArchiveRequestError.invalidOutputFileName)
                continue
            }
            do {
                currentRequest = try FinderArchiveRequest(
                    sourceURLs: currentRequest.sourceURLs,
                    destinationDirectoryURL: currentRequest.destinationURL.deletingLastPathComponent(),
                    outputFileName: outputFileName
                )
            } catch {
                showArchiveRequestValidation(for: error)
                continue
            }
            if first.stringValue.count < 8 {
                showValidation(message: "密码至少需要 8 个字符。")
                continue
            }
            if first.stringValue != confirmation.stringValue {
                showValidation(message: "两次输入的密码不一致。")
                continue
            }
            return FinderArchiveCreationChoice(
                password: first.stringValue,
                request: currentRequest
            )
        }
    }

    static func requestExistingPassword() -> String? {
        let field = secureTextField(placeholder: "输入 ZIP 密码")
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "这个 ZIP 已加密"
        alert.informativeText = "请输入密码后再解压。密码不会保存。"
        alert.accessoryView = passwordAccessory(rows: [("密码", field)])
        alert.addButton(withTitle: "解压")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    private static func passwordAccessory(rows: [(String, PasswordEntryControl)]) -> NSView {
        let gridRows: [[NSView]] = rows.map { title, field in
            let label = NSTextField(labelWithString: title)
            label.alignment = .right
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 250).isActive = true
            field.heightAnchor.constraint(equalToConstant: 28).isActive = true
            return [label, field]
        }
        let grid = NSGridView(views: gridRows)
        NSLayoutConstraint.activate(gridRows.map { row in
            row[0].centerYAnchor.constraint(equalTo: row[1].centerYAnchor)
        })
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        for rowIndex in gridRows.indices {
            grid.row(at: rowIndex).yPlacement = .center
        }
        grid.frame = NSRect(x: 0, y: 0, width: 320, height: max(28, rows.count * 30))
        return grid
    }

    private static func finderArchiveAccessory(
        locationController: FinderArchiveLocationController,
        sourceRequest: FinderArchiveRequest,
        password: PasswordEntryControl,
        confirmation: PasswordEntryControl
    ) -> NSView {
        let header = finderArchiveHeader()
        let target = singleLineDetailLabel(sourceRequest.targetSummary)
        target.toolTip = sourceRequest.sourceURLs.map(\.path).joined(separator: "\n")
        let targetGrid = formGrid(rows: [("压缩目标", target)])

        let controls: [(String, NSView)] = [
            ("输出文件", locationController.makeOutputFileControl()),
            ("加密密码", password),
            ("确认密码", confirmation),
        ]
        let grid = formGrid(rows: controls)

        let stack = NSStackView(views: [
            header,
            targetGrid,
            grid,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(16, after: header)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 178))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            header.widthAnchor.constraint(equalToConstant: 500),
        ])
        return container
    }

    private static func finderArchiveHeader() -> NSView {
        passwordDialogHeader(
            title: "设置文件加密压缩密码",
            accessibilityIdentifier: "finder-archive-password-title"
        )
    }

    private static func singleLineDetailLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        return label
    }

    private static func formGrid(rows controls: [(String, NSView)]) -> NSGridView {
        let rows: [[NSView]] = controls.map { title, control in
            let label = NSTextField(labelWithString: title)
            label.alignment = .right
            label.font = .systemFont(ofSize: 13, weight: .medium)
            control.translatesAutoresizingMaskIntoConstraints = false
            control.widthAnchor.constraint(equalToConstant: 436).isActive = true
            if control is ArchiveFileNameControl || control is PasswordEntryControl {
                control.heightAnchor.constraint(equalToConstant: 28).isActive = true
            } else if let field = control as? NSTextField, field.isEditable {
                control.heightAnchor.constraint(equalToConstant: 28).isActive = true
            } else if control is NSControl, !(control is NSTextField) {
                control.heightAnchor.constraint(equalToConstant: 28).isActive = true
            }
            return [label, control]
        }
        let grid = NSGridView(views: rows)
        NSLayoutConstraint.activate(controls.indices.map { rowIndex in
            rows[rowIndex][0].centerYAnchor.constraint(
                equalTo: rows[rowIndex][1].centerYAnchor
            )
        })
        grid.rowSpacing = 8
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        for rowIndex in rows.indices {
            grid.row(at: rowIndex).yPlacement = .center
        }
        return grid
    }

    private static func secureTextField(
        placeholder: String,
        value: String = "",
        visibilityIdentifier: String = "password-visibility"
    ) -> PasswordEntryControl {
        PasswordEntryControl(
            placeholder: placeholder,
            value: value,
            visibilityIdentifier: visibilityIdentifier
        )
    }

    private static func showValidation(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "请检查密码"
        alert.informativeText = message
        alert.addButton(withTitle: "重新输入")
        alert.runModal()
    }

    private static func editableOutputFileName(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasSuffix(".zip") {
            let baseName = String(trimmed.dropLast(4))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return baseName.isEmpty ? nil : baseName
        }
        return trimmed
    }

    private static func showArchiveRequestValidation(for error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        if error as? FinderArchiveRequestError == .invalidOutputFileName {
            alert.messageText = "无法使用这个输出文件名"
            alert.informativeText = "请输入普通文件名，不要包含路径、斜杠、反斜杠或冒号。.zip 扩展名由应用固定添加。"
        } else {
            alert.messageText = "无法使用这个保存位置"
            alert.informativeText = "请选择一个仍然存在且可以访问的文件夹。"
        }
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

@MainActor
private struct FinderArchivePasswordValidation {
    let title: String
    let message: String
    let buttonTitle: String
    let firstResponder: NSView?
}

@MainActor
private final class FinderArchivePasswordDialog: NSObject {
    private let panel: NSPanel
    private weak var initialFirstResponder: NSView?
    private let validationHandler: () -> FinderArchivePasswordValidation?

    init(
        accessoryView: NSView,
        randomPasswordButton: NSButton,
        initialFirstResponder: NSView,
        validationHandler: @escaping () -> FinderArchivePasswordValidation?
    ) {
        self.initialFirstResponder = initialFirstResponder
        self.validationHandler = validationHandler

        let accessorySize = accessoryView.frame.size
        let contentSize = NSSize(
            width: accessorySize.width + 40,
            height: accessorySize.height + 88
        )
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .windowBackgroundColor
        panel.level = .modalPanel
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let cancelButton = NSButton(
            title: "取消",
            target: self,
            action: #selector(cancel(_:))
        )
        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .large
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.setAccessibilityIdentifier("action-button-2")

        let createButton = NSButton(
            title: "创建",
            target: self,
            action: #selector(create(_:))
        )
        createButton.bezelStyle = .rounded
        createButton.controlSize = .large
        createButton.keyEquivalent = "\r"
        createButton.setAccessibilityIdentifier("action-button-1")

        randomPasswordButton.bezelStyle = .rounded
        randomPasswordButton.controlSize = .large

        let buttons = NSStackView(views: [
            cancelButton,
            randomPasswordButton,
            createButton,
        ])
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
            cancelButton.widthAnchor.constraint(equalToConstant: 110),
            randomPasswordButton.widthAnchor.constraint(equalToConstant: 110),
            createButton.widthAnchor.constraint(equalToConstant: 110),
            cancelButton.heightAnchor.constraint(equalToConstant: 32),
            randomPasswordButton.heightAnchor.constraint(equalToConstant: 32),
            createButton.heightAnchor.constraint(equalToConstant: 32),
        ])
        panel.defaultButtonCell = createButton.cell as? NSButtonCell
    }

    func runModal() -> NSApplication.ModalResponse {
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        if let initialFirstResponder {
            if let passwordEntry = initialFirstResponder as? PasswordEntryControl {
                passwordEntry.focus()
            } else {
                panel.makeFirstResponder(initialFirstResponder)
            }
        }
        let response = NSApp.runModal(for: panel)
        panel.orderOut(nil)
        return response
    }

    @objc private func create(_ sender: NSButton) {
        if let validation = validationHandler() {
            showValidation(validation)
            return
        }
        NSApp.stopModal(withCode: .alertFirstButtonReturn)
    }

    @objc private func cancel(_ sender: NSButton) {
        NSApp.stopModal(withCode: .alertSecondButtonReturn)
    }

    private func showValidation(_ validation: FinderArchivePasswordValidation) {
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
private final class FinderArchiveLocationController: NSObject {
    private(set) var request: FinderArchiveRequest
    private var passwordGenerationController: GeneratedPasswordController?
    let outputFileControl: ArchiveFileNameControl

    init(request: FinderArchiveRequest, outputFileName: String) {
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
                request = try FinderArchiveRequest(
                    sourceURLs: request.sourceURLs,
                    destinationDirectoryURL: directory,
                    outputFileName: preservedName
                )
                refreshLabels()
            } catch {
                showDirectorySelectionFailure(for: error, on: parentWindow)
            }
        }
    }

    private func showDirectorySelectionFailure(for error: Error, on window: NSWindow) {
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

@MainActor
private final class GeneratedPasswordController: NSObject {
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
private final class GeneratedPasswordDialog: NSObject {
    struct Choice {
        let confirmed: Bool
        let copyToPasteboard: Bool
    }

    private let panel: NSPanel
    private let copyCheckbox: NSButton

    init(password: String) {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 380, height: 242)),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        copyCheckbox = NSButton(
            checkboxWithTitle: "确定后复制密码到剪贴板",
            target: nil,
            action: nil
        )
        super.init()

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .windowBackgroundColor
        panel.level = .modalPanel
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let header = passwordDialogHeader(
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
        if let parentWindow {
            let parentFrame = parentWindow.frame
            let panelFrame = panel.frame
            panel.setFrameOrigin(NSPoint(
                x: parentFrame.midX - panelFrame.width / 2,
                y: parentFrame.midY - panelFrame.height / 2
            ))
        } else {
            panel.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        let response = NSApp.runModal(for: panel)
        panel.orderOut(nil)
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

@MainActor
private func passwordDialogHeader(
    title: String,
    accessibilityIdentifier: String
) -> NSView {
    let iconView = NSImageView()
    iconView.image = NSApp.applicationIconImage
    iconView.imageScaling = .scaleProportionallyUpOrDown
    iconView.translatesAutoresizingMaskIntoConstraints = false
    iconView.setAccessibilityLabel("aulycZip")

    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
    titleLabel.textColor = .labelColor
    titleLabel.setAccessibilityIdentifier(accessibilityIdentifier)

    let row = NSStackView(views: [iconView, titleLabel])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 10
    row.translatesAutoresizingMaskIntoConstraints = false

    let container = NSView()
    container.addSubview(row)
    NSLayoutConstraint.activate([
        iconView.widthAnchor.constraint(equalToConstant: 30),
        iconView.heightAnchor.constraint(equalToConstant: 30),
        row.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        row.topAnchor.constraint(equalTo: container.topAnchor),
        row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
    return container
}

@MainActor
private final class ArchiveFileNameControl: NSView, NSTextFieldDelegate {
    private let fieldBackground = NSBox()
    private let directoryLabel = NSTextField(frame: .zero)
    private let baseNameField = NSTextField(frame: .zero)
    private let suffixLabel = NSTextField(frame: .zero)
    private var baseNameWidthConstraint: NSLayoutConstraint!
    private var isEditing = false

    var directoryPath: String {
        get {
            let value = directoryLabel.stringValue
            return value == "/" ? value : String(value.dropLast())
        }
        set {
            let path = newValue == "/" ? "/" : newValue + "/"
            directoryLabel.stringValue = path
            directoryLabel.toolTip = newValue
            refreshToolTip()
        }
    }

    var baseName: String {
        get { baseNameField.stringValue }
        set {
            baseNameField.stringValue = normalizedBaseName(newValue)
            updateBaseNameWidth()
            refreshToolTip()
        }
    }

    init(baseName: String) {
        super.init(frame: .zero)

        baseNameField.isBezeled = false
        baseNameField.drawsBackground = false
        baseNameField.isEditable = true
        baseNameField.isSelectable = true
        baseNameField.focusRingType = .none
        baseNameField.font = .systemFont(ofSize: 13)
        baseNameField.placeholderString = "输出文件名"
        baseNameField.stringValue = normalizedBaseName(baseName)
        baseNameField.delegate = self
        baseNameField.toolTip = "可以修改文件名；.zip 扩展名固定，不可修改"
        baseNameField.setAccessibilityLabel("输出文件名，不含固定的 .zip 扩展名")
        baseNameField.setAccessibilityIdentifier("archive-output-file-base-name")

        fieldBackground.boxType = .custom
        fieldBackground.borderWidth = 1
        fieldBackground.cornerRadius = 5
        fieldBackground.borderColor = .separatorColor
        fieldBackground.fillColor = .controlBackgroundColor
        fieldBackground.titlePosition = .noTitle
        fieldBackground.translatesAutoresizingMaskIntoConstraints = false

        directoryLabel.font = .systemFont(ofSize: 13)
        directoryLabel.isBezeled = false
        directoryLabel.drawsBackground = false
        directoryLabel.isEditable = false
        directoryLabel.isSelectable = false
        directoryLabel.focusRingType = .none
        directoryLabel.textColor = .secondaryLabelColor
        directoryLabel.lineBreakMode = .byTruncatingMiddle
        directoryLabel.maximumNumberOfLines = 1
        directoryLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        directoryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        suffixLabel.font = .systemFont(ofSize: 13, weight: .medium)
        suffixLabel.stringValue = ".zip"
        suffixLabel.isBezeled = false
        suffixLabel.drawsBackground = false
        suffixLabel.isEditable = false
        suffixLabel.isSelectable = false
        suffixLabel.focusRingType = .none
        suffixLabel.textColor = .secondaryLabelColor
        suffixLabel.alignment = .left
        suffixLabel.toolTip = "ZIP 扩展名固定，不可修改"

        let stack = NSStackView(views: [directoryLabel, baseNameField, suffixLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 0
        stack.setCustomSpacing(4, after: directoryLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fieldBackground)
        addSubview(stack)

        baseNameField.setContentHuggingPriority(.required, for: .horizontal)
        baseNameField.setContentCompressionResistancePriority(.required, for: .horizontal)
        suffixLabel.setContentHuggingPriority(.required, for: .horizontal)
        suffixLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        baseNameWidthConstraint = baseNameField.widthAnchor.constraint(
            equalToConstant: preferredBaseNameWidth()
        )
        baseNameWidthConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([
            fieldBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            fieldBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            fieldBackground.topAnchor.constraint(equalTo: topAnchor),
            fieldBackground.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.heightAnchor.constraint(equalToConstant: 16),
            directoryLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.5),
            baseNameWidthConstraint,
            baseNameField.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.62),
            directoryLabel.heightAnchor.constraint(equalTo: stack.heightAnchor),
            baseNameField.heightAnchor.constraint(equalTo: stack.heightAnchor),
            suffixLabel.heightAnchor.constraint(equalTo: stack.heightAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didUpdateNotification,
            object: nil
        )
        if let window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidUpdate(_:)),
                name: NSWindow.didUpdateNotification,
                object: window
            )
        }
        refreshFocusedAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateFocusBorder()
    }

    func controlTextDidChange(_ notification: Notification) {
        let normalized = normalizedBaseName(baseNameField.stringValue)
        if normalized != baseNameField.stringValue {
            baseNameField.stringValue = normalized
        }
        updateBaseNameWidth()
        refreshToolTip()
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        setFocusedAppearance(true)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        setFocusedAppearance(false)
    }

    @objc private func windowDidUpdate(_ notification: Notification) {
        refreshFocusedAppearance()
    }

    override func becomeFirstResponder() -> Bool {
        window?.makeFirstResponder(baseNameField) ?? false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0, bounds.contains(point) else { return nil }
        return self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        guard window?.makeFirstResponder(baseNameField) == true else { return }

        let pointInField = baseNameField.convert(event.locationInWindow, from: nil)
        if baseNameField.bounds.contains(pointInField) {
            baseNameField.mouseDown(with: event)
            return
        }

        guard let editor = baseNameField.currentEditor() as? NSTextView else { return }
        // The path and suffix are read-only parts of one visual field. Clicking the
        // path starts at the beginning; clicking the suffix or trailing area moves
        // to the end, while keeping the fixed .zip outside the editable selection.
        let location = pointInField.x < baseNameField.bounds.minX
            ? 0
            : baseNameField.stringValue.utf16.count
        let range = NSRange(location: location, length: 0)
        editor.setSelectedRange(range)
        editor.scrollRangeToVisible(range)
    }

    private func setFocusedAppearance(_ focused: Bool) {
        guard isEditing != focused else { return }
        isEditing = focused
        updateFocusBorder()
    }

    private func refreshFocusedAppearance() {
        let editor = baseNameField.currentEditor()
        setFocusedAppearance(editor != nil && window?.firstResponder === editor)
    }

    private func updateFocusBorder() {
        fieldBackground.borderWidth = 1
        fieldBackground.borderColor = isEditing
            ? .keyboardFocusIndicatorColor
            : .separatorColor
        fieldBackground.needsDisplay = true
    }

    private func normalizedBaseName(_ value: String) -> String {
        value.lowercased().hasSuffix(".zip") ? String(value.dropLast(4)) : value
    }

    private func updateBaseNameWidth() {
        baseNameWidthConstraint?.constant = preferredBaseNameWidth()
    }

    private func preferredBaseNameWidth() -> CGFloat {
        let visibleText = baseNameField.stringValue.isEmpty
            ? (baseNameField.placeholderString ?? "")
            : baseNameField.stringValue
        let font = baseNameField.font ?? .systemFont(ofSize: 13)
        let textWidth = ceil(
            (visibleText as NSString).size(withAttributes: [.font: font]).width
        )
        return min(220, max(12, textWidth + 2))
    }

    private func refreshToolTip() {
        let directory = directoryLabel.stringValue
        toolTip = directory.isEmpty ? nil : directory + baseNameField.stringValue + ".zip"
    }
}

private final class PasswordEntryControl: NSView {
    private let fieldBackground = NSBox()
    private let secureField = NSSecureTextField(frame: .zero)
    private let visibleField = NSTextField(frame: .zero)
    private let secureFocusDelegate = ThinFocusTextFieldDelegate()
    private let visibleFocusDelegate = ThinFocusTextFieldDelegate()
    private let visibilityButton = NSButton(frame: .zero)
    private var isEditing = false

    var stringValue: String {
        get { activeField.stringValue }
        set {
            secureField.stringValue = newValue
            visibleField.stringValue = isPasswordVisible ? newValue : ""
        }
    }

    var isPasswordVisible = false {
        didSet {
            guard isPasswordVisible != oldValue else { return }
            switchPasswordVisibility()
            updateVisibilityButton()
        }
    }

    private var activeField: NSTextField {
        isPasswordVisible ? visibleField : secureField
    }

    init(placeholder: String, value: String, visibilityIdentifier: String) {
        super.init(frame: .zero)

        configure(field: secureField, placeholder: placeholder, value: value)
        configure(field: visibleField, placeholder: placeholder, value: "")
        secureField.delegate = secureFocusDelegate
        visibleField.delegate = visibleFocusDelegate
        visibleField.isHidden = true

        fieldBackground.boxType = .custom
        fieldBackground.borderWidth = 1
        fieldBackground.cornerRadius = 5
        fieldBackground.borderColor = .separatorColor
        fieldBackground.fillColor = .controlBackgroundColor
        fieldBackground.titlePosition = .noTitle
        fieldBackground.translatesAutoresizingMaskIntoConstraints = false

        secureFocusDelegate.onFocusChanged = { [weak self] focused in
            self?.setFocusedAppearance(focused)
        }
        visibleFocusDelegate.onFocusChanged = { [weak self] focused in
            self?.setFocusedAppearance(focused)
        }

        visibilityButton.target = self
        visibilityButton.action = #selector(togglePasswordVisibility(_:))
        visibilityButton.isBordered = false
        visibilityButton.bezelStyle = .accessoryBarAction
        visibilityButton.imagePosition = .imageOnly
        visibilityButton.imageScaling = .scaleProportionallyDown
        visibilityButton.contentTintColor = .secondaryLabelColor
        visibilityButton.refusesFirstResponder = true
        visibilityButton.setAccessibilityIdentifier(visibilityIdentifier)
        visibilityButton.translatesAutoresizingMaskIntoConstraints = false
        updateVisibilityButton()

        addSubview(fieldBackground)
        addSubview(secureField)
        addSubview(visibleField)
        addSubview(visibilityButton)
        NSLayoutConstraint.activate([
            fieldBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            fieldBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            fieldBackground.topAnchor.constraint(equalTo: topAnchor),
            fieldBackground.bottomAnchor.constraint(equalTo: bottomAnchor),
            secureField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            secureField.trailingAnchor.constraint(equalTo: visibilityButton.leadingAnchor, constant: -4),
            secureField.centerYAnchor.constraint(equalTo: centerYAnchor),
            secureField.heightAnchor.constraint(equalToConstant: 16),
            visibleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            visibleField.trailingAnchor.constraint(equalTo: visibilityButton.leadingAnchor, constant: -4),
            visibleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            visibleField.heightAnchor.constraint(equalToConstant: 16),
            visibilityButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            visibilityButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            visibilityButton.widthAnchor.constraint(equalToConstant: 22),
            visibilityButton.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func becomeFirstResponder() -> Bool {
        focus()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateFocusBorder()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didUpdateNotification,
            object: nil
        )
        if let window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidUpdate(_:)),
                name: NSWindow.didUpdateNotification,
                object: window
            )
        }
        refreshFocusedAppearance()
    }

    @discardableResult
    func focus() -> Bool {
        let focused = window?.makeFirstResponder(activeField) ?? false
        if focused {
            (isPasswordVisible ? visibleFocusDelegate : secureFocusDelegate)
                .setFocusedAppearance(true)
        }
        return focused
    }

    @objc private func togglePasswordVisibility(_ sender: NSButton) {
        isPasswordVisible.toggle()
    }

    @objc private func windowDidUpdate(_ notification: Notification) {
        refreshFocusedAppearance()
    }

    private func updateVisibilityButton() {
        let title = isPasswordVisible ? "隐藏密码" : "显示密码"
        let symbolName = isPasswordVisible ? "eye.slash" : "eye"
        visibilityButton.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: title
        )
        visibilityButton.toolTip = title
        visibilityButton.setAccessibilityLabel(title)
    }

    private func configure(field: NSTextField, placeholder: String, value: String) {
        // Hidden mode remains a native NSSecureTextField. The visible peer is also
        // a native AppKit text field and exists only for an explicit reveal action.
        field.translatesAutoresizingMaskIntoConstraints = false
        field.focusRingType = .none
        field.isBezeled = false
        field.drawsBackground = false
        field.isEditable = true
        field.isSelectable = true
        field.font = .systemFont(ofSize: 13)
        field.placeholderString = placeholder
        field.stringValue = value
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
    }

    private func setFocusedAppearance(_ focused: Bool) {
        guard isEditing != focused else { return }
        isEditing = focused
        updateFocusBorder()
    }

    private func refreshFocusedAppearance() {
        let editor = activeField.currentEditor()
        setFocusedAppearance(editor != nil && window?.firstResponder === editor)
    }

    private func updateFocusBorder() {
        fieldBackground.borderWidth = 1
        fieldBackground.borderColor = isEditing
            ? .keyboardFocusIndicatorColor
            : .separatorColor
        fieldBackground.needsDisplay = true
    }

    private func switchPasswordVisibility() {
        let previousField = isPasswordVisible ? secureField : visibleField
        let nextField = activeField
        let currentValue = previousField.stringValue
        let previousEditor = previousField.currentEditor() as? NSTextView
        let selectedRange = previousEditor?.selectedRange()

        if isPasswordVisible {
            visibleField.stringValue = currentValue
        } else {
            secureField.stringValue = currentValue
        }
        secureField.isHidden = isPasswordVisible
        visibleField.isHidden = !isPasswordVisible
        defer {
            if !isPasswordVisible {
                visibleField.stringValue = ""
            }
        }

        guard previousEditor != nil, window?.makeFirstResponder(nextField) == true else {
            return
        }
        if let selectedRange,
           let nextEditor = nextField.currentEditor() as? NSTextView {
            nextEditor.setSelectedRange(selectedRange)
            nextEditor.scrollRangeToVisible(selectedRange)
        }
    }
}

private final class ThinFocusTextFieldDelegate: NSObject, NSTextFieldDelegate {
    private var isEditing = false
    var onFocusChanged: ((Bool) -> Void)?

    func controlTextDidBeginEditing(_ notification: Notification) {
        setFocusedAppearance(true)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        setFocusedAppearance(false)
    }

    func setFocusedAppearance(_ focused: Bool) {
        guard isEditing != focused else { return }
        isEditing = focused
        onFocusChanged?(focused)
    }
}
