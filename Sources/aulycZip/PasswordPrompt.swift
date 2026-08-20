import AppKit
import ZipCore
import aulycZipAppSupport

struct FinderArchiveCreationChoice: Sendable {
    let password: String
    let request: FinderArchiveRequest
}

struct ArchiveExtractionChoice: Sendable {
    let destinationURL: URL
    let destinationPolicy: ZipExtractionDestinationPolicy
    let password: String?
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

            if let validation = newPasswordValidation(
                password: first,
                confirmation: confirmation
            ) {
                showValidation(validation)
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
                supplementaryButton: randomPasswordButton,
                primaryButtonTitle: "创建",
                initialFirstResponder: first,
                validationHandler: {
                    if let validation = newPasswordValidation(
                        password: first,
                        confirmation: confirmation
                    ) {
                        return validation
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
            if let validation = newPasswordValidation(
                password: first,
                confirmation: confirmation
            ) {
                showValidation(validation)
                continue
            }
            return FinderArchiveCreationChoice(
                password: first.stringValue,
                request: currentRequest
            )
        }
    }

    static func requestExtractionChoice(
        for archiveURL: URL,
        requiresPassword: Bool
    ) -> ArchiveExtractionChoice? {
        let passwordField = requiresPassword
            ? secureTextField(
                placeholder: "输入解压缩密码",
                visibilityIdentifier: "extract-password-visibility"
            )
            : nil
        let locationController = ArchiveExtractionLocationController(archiveURL: archiveURL)
        let accessory = archiveExtractionAccessory(
            archiveURL: archiveURL,
            locationController: locationController,
            password: passwordField
        )
        let dialog = FinderArchivePasswordDialog(
            accessoryView: accessory,
            primaryButtonTitle: "解压",
            initialFirstResponder: passwordField,
            validationHandler: {
                locationController.validateSelection()
            }
        )
        guard dialog.runModal() == .alertFirstButtonReturn else { return nil }
        return ArchiveExtractionChoice(
            destinationURL: locationController.destinationURL,
            destinationPolicy: locationController.destinationPolicy,
            password: passwordField?.stringValue
        )
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

    private static func archiveExtractionAccessory(
        archiveURL: URL,
        locationController: ArchiveExtractionLocationController,
        password: PasswordEntryControl?
    ) -> NSView {
        let header = passwordDialogHeader(
            title: "设置 ZIP 解压缩",
            accessibilityIdentifier: "archive-extraction-title"
        )
        let target = singleLineDetailLabel(archiveURL.path)
        target.toolTip = archiveURL.path
        let targetGrid = formGrid(rows: [("解压目标", target)])

        var controls: [(String, NSView)] = [
            ("输出文件夹", locationController.makeOutputDirectoryControl()),
            ("", locationController.makeIndependentFolderCheckbox()),
        ]
        if let password {
            controls.append(("解压密码", password))
        }
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

        let height: CGFloat = password == nil ? 148 : 184
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: height))
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

    private static func newPasswordValidation(
        password: PasswordEntryControl,
        confirmation: PasswordEntryControl
    ) -> FinderArchivePasswordValidation? {
        guard let failure = ArchivePasswordValidator.validateNewPassword(
            password.stringValue,
            confirmation: confirmation.stringValue
        ) else {
            return nil
        }
        return FinderArchivePasswordValidation(
            title: "请检查密码",
            message: failure.message,
            buttonTitle: "重新输入",
            firstResponder: failure == .tooShort ? password : confirmation
        )
    }

    private static func showValidation(_ validation: FinderArchivePasswordValidation) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = validation.title
        alert.informativeText = validation.message
        alert.addButton(withTitle: validation.buttonTitle)
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
