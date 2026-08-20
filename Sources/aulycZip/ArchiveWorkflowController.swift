import AppKit
import UniformTypeIdentifiers
import ZipCore
import aulycZipAppSupport

private enum WorkflowOutcome: Sendable {
    case success
    case cancelled
    case zipFailure(ZipError)
    case systemFailure(String)
}

private enum ListingOutcome: Sendable {
    case success([ZipEntry])
    case cancelled
    case zipFailure(ZipError)
    case systemFailure(String)
}

private enum CompletionPresentation {
    case systemAlert
    case appHeader
}

@MainActor
final class ArchiveWorkflowController {
    private let progress = ProgressPanelController()
    private let aboutWindowController = AboutWindowController()
    private let operationCoordinator: AppOperationCoordinator

    init(operationCoordinator: AppOperationCoordinator) {
        self.operationCoordinator = operationCoordinator
    }

    func createEncryptedArchive() {
        guard beginUserFlow() else { return }

        let sourcePanel = NSOpenPanel()
        sourcePanel.title = "选择要加密压缩的文件或文件夹"
        sourcePanel.prompt = "选择"
        sourcePanel.canChooseFiles = true
        sourcePanel.canChooseDirectories = true
        sourcePanel.allowsMultipleSelection = true
        sourcePanel.resolvesAliases = false
        guard sourcePanel.runModal() == .OK, !sourcePanel.urls.isEmpty else {
            operationCoordinator.end(.archive)
            return
        }

        let destinationPanel = NSSavePanel()
        destinationPanel.title = "保存加密 ZIP"
        destinationPanel.prompt = "保存"
        destinationPanel.allowedContentTypes = [.zip]
        destinationPanel.canCreateDirectories = true
        destinationPanel.directoryURL = sourcePanel.urls.first?.deletingLastPathComponent()
        destinationPanel.nameFieldStringValue = suggestedArchiveName(for: sourcePanel.urls)
        guard destinationPanel.runModal() == .OK, let destination = destinationPanel.url else {
            operationCoordinator.end(.archive)
            return
        }
        let destinationPolicy: ZipCreationDestinationPolicy = FileManager.default.fileExists(
            atPath: destination.path
        ) ? .replaceExisting : .refuseExisting

        guard let password = PasswordPrompt.requestNewPassword() else {
            operationCoordinator.end(.archive)
            return
        }
        startMenuEncryptedCreation(
            sourceURLs: sourcePanel.urls,
            destination: destination,
            destinationPolicy: destinationPolicy,
            password: password
        )
    }

    func createEncryptedArchiveFromFinder(_ sourceURLs: [URL]) {
        guard beginUserFlow() else { return }
        let request: FinderArchiveRequest
        do {
            request = try FinderArchiveRequest(sourceURLs: sourceURLs)
        } catch {
            operationCoordinator.end(.archive)
            presentErrorMessage("Finder 没有提供可压缩的文件或文件夹。")
            return
        }
        guard let choice = PasswordPrompt.requestNewPassword(for: request) else {
            operationCoordinator.end(.archive)
            return
        }
        startFinderEncryptedCreation(choice)
    }

    private func startMenuEncryptedCreation(
        sourceURLs: [URL],
        destination: URL,
        destinationPolicy: ZipCreationDestinationPolicy,
        password: String
    ) {
        performEncryptedCreation(destination: destination) { cancellation in
            try ZipArchive.create(
                at: destination,
                contentsOf: sourceURLs,
                encryption: .winZipAES256(password: password),
                destinationPolicy: destinationPolicy,
                cancellation: cancellation
            )
        }
    }

    private func startFinderEncryptedCreation(_ choice: FinderArchiveCreationChoice) {
        performEncryptedCreation(destination: choice.request.destinationURL) { cancellation in
            _ = try FinderEncryptedArchiveCreator.create(
                request: choice.request,
                password: choice.password,
                cancellation: cancellation
            )
        }
    }

    private func performEncryptedCreation(
        destination: URL,
        operation: @escaping @Sendable (ZipOperationCancellation) throws -> Void
    ) {
        let cancellation = ZipOperationCancellation()
        progress.showOperation(
            title: "正在创建加密 ZIP",
            detail: destination.lastPathComponent,
            onCancel: { cancellation.cancel() }
        )
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                do {
                    try operation(cancellation)
                    return WorkflowOutcome.success
                } catch ZipError.cancelled {
                    return WorkflowOutcome.cancelled
                } catch FinderEncryptedArchiveCreationError.destinationExists {
                    return WorkflowOutcome.systemFailure(
                        "同名 ZIP 在操作过程中出现，原文件没有被覆盖。请重新执行右键加密压缩。"
                    )
                } catch let error as ZipError {
                    return WorkflowOutcome.zipFailure(error)
                } catch {
                    return WorkflowOutcome.systemFailure(error.localizedDescription)
                }
            }.value
            operationCoordinator.end(.archive)
            progress.dismiss()
            handleCompletion(
                outcome,
                successTitle: "加密 ZIP 已创建",
                successMessage: destination.path,
                reveal: destination,
                presentation: .appHeader
            )
        }
    }

    func extractArchive() {
        guard beginUserFlow() else { return }

        let archivePanel = NSOpenPanel()
        archivePanel.title = "选择要解压的 ZIP"
        archivePanel.prompt = "选择"
        archivePanel.canChooseFiles = true
        archivePanel.canChooseDirectories = false
        archivePanel.allowsMultipleSelection = false
        archivePanel.allowedContentTypes = [.zip]
        guard archivePanel.runModal() == .OK, let archive = archivePanel.url else {
            operationCoordinator.end(.archive)
            return
        }

        let cancellation = ZipOperationCancellation()
        progress.showOperation(
            title: "正在读取 ZIP",
            detail: archive.lastPathComponent,
            onCancel: { cancellation.cancel() }
        )
        Task {
            let listing = await Task.detached(priority: .userInitiated) {
                do {
                    return ListingOutcome.success(
                        try ZipArchive.list(archive, cancellation: cancellation)
                    )
                } catch ZipError.cancelled {
                    return ListingOutcome.cancelled
                } catch let error as ZipError {
                    return ListingOutcome.zipFailure(error)
                } catch {
                    return ListingOutcome.systemFailure(error.localizedDescription)
                }
            }.value
            progress.dismiss()

            let entries: [ZipEntry]
            switch listing {
            case .success(let listedEntries):
                entries = listedEntries
            case .cancelled:
                operationCoordinator.end(.archive)
                return
            case .zipFailure(let error):
                operationCoordinator.end(.archive)
                presentError(error)
                return
            case .systemFailure(let message):
                operationCoordinator.end(.archive)
                presentErrorMessage(message)
                return
            }

            guard !entries.isEmpty else {
                operationCoordinator.end(.archive)
                presentErrorMessage("这个 ZIP 中没有可解压的内容。")
                return
            }

            guard let choice = PasswordPrompt.requestExtractionChoice(
                for: archive,
                requiresPassword: entries.contains(where: \.isEncrypted)
            ) else {
                operationCoordinator.end(.archive)
                return
            }

            let destination = choice.destinationURL
            progress.showOperation(
                title: "正在解压 ZIP",
                detail: archive.lastPathComponent,
                onCancel: { cancellation.cancel() }
            )
            let outcome = await Task.detached(priority: .userInitiated) {
                do {
                    try ZipArchive.extract(
                        archive,
                        to: destination,
                        password: choice.password,
                        destinationPolicy: choice.destinationPolicy,
                        cancellation: cancellation
                    )
                    return WorkflowOutcome.success
                } catch ZipError.cancelled {
                    return WorkflowOutcome.cancelled
                } catch let error as ZipError {
                    return WorkflowOutcome.zipFailure(error)
                } catch {
                    return WorkflowOutcome.systemFailure(error.localizedDescription)
                }
            }.value
            operationCoordinator.end(.archive)
            progress.dismiss()
            handleCompletion(
                outcome,
                successTitle: "ZIP 已解压",
                successMessage: destination.path,
                reveal: destination,
                presentation: .appHeader
            )
        }
    }

    func showAbout() {
        aboutWindowController.show()
    }

    private func beginUserFlow() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        guard operationCoordinator.begin(.archive) else {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "已有任务正在进行"
            alert.informativeText = "请等待当前压缩、解压或更新替换完成。"
            alert.runModal()
            return false
        }
        return true
    }

    private func suggestedArchiveName(for sources: [URL]) -> String {
        if sources.count == 1, let first = sources.first {
            let baseName = first.deletingPathExtension().lastPathComponent
            if first.pathExtension.caseInsensitiveCompare("zip") == .orderedSame {
                return baseName + " 加密.zip"
            }
            return baseName + ".zip"
        }
        return "归档.zip"
    }

    private func handleCompletion(
        _ outcome: WorkflowOutcome,
        successTitle: String,
        successMessage: String,
        reveal: URL,
        presentation: CompletionPresentation = .systemAlert
    ) {
        switch outcome {
        case .success:
            let response: NSApplication.ModalResponse
            switch presentation {
            case .systemAlert:
                let alert = NSAlert()
                alert.messageText = successTitle
                alert.informativeText = successMessage
                alert.addButton(withTitle: "在 Finder 中显示")
                alert.addButton(withTitle: "完成")
                response = alert.runModal()
            case .appHeader:
                let dialog = WorkflowCompletionDialog(
                    title: successTitle,
                    message: successMessage
                )
                response = dialog.runModal()
            }
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([reveal])
            }
        case .cancelled:
            break
        case .zipFailure(let error):
            presentError(error)
        case .systemFailure(let message):
            presentErrorMessage(message)
        }
    }

    private func presentError(_ error: ZipError) {
        let message: String
        switch error {
        case .wrongPassword:
            message = "密码不正确。"
        case .authenticationFailed:
            message = "密码不正确，或 ZIP 内容已损坏、被篡改。未写出未经验证的文件。"
        case .unsafeEntryPath:
            message = "ZIP 中包含不安全的文件路径，已停止解压。"
        case .outputLimitExceeded:
            message = "解压后的数据超过安全限制，已停止解压。"
        case .tooManyEntries:
            message = "ZIP 中的文件数量超过安全限制。"
        case .duplicateEntry(let path):
            message = "存在重复文件名：\(path)"
        case .destinationMatchesSource:
            message = "输出 ZIP 不能覆盖作为输入的文件，请换一个文件名或保存位置。"
        case .destinationAlreadyExists:
            message = "目标位置已经存在同名文件或文件夹，未执行覆盖。"
        case .destinationEntryAlreadyExists(let path):
            message = "输出位置已有同名项目：\(URL(fileURLWithPath: path).lastPathComponent)。未覆盖任何内容。请勾选“解压到独立文件夹”后重试。"
        case .unsupportedFeature(let reason):
            message = "暂不支持这个 ZIP：\(reason)"
        case .invalidArchive(let reason):
            message = "ZIP 格式无效：\(reason)"
        case .truncatedArchive:
            message = "ZIP 数据不完整，文件可能已损坏。"
        case .cancelled:
            message = "操作已取消，临时文件已经清理。"
        }
        presentErrorMessage(message)
    }

    private func presentErrorMessage(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "操作未完成"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
