import AppKit
import UniformTypeIdentifiers
import ZipCore
import aulycZipAppSupport

private enum WorkflowOutcome: Sendable {
    case success
    case zipFailure(ZipError)
    case systemFailure(String)
}

private enum ListingOutcome: Sendable {
    case success([ZipEntry])
    case zipFailure(ZipError)
    case systemFailure(String)
}

@MainActor
final class ArchiveWorkflowController {
    private let progress = OperationProgressPanelController()
    private let aboutWindowController = AboutWindowController()
    private var isBusy = false

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
            isBusy = false
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
            isBusy = false
            return
        }

        guard let password = PasswordPrompt.requestNewPassword() else {
            isBusy = false
            return
        }
        startEncryptedCreation(
            sourceURLs: sourcePanel.urls,
            destination: destination,
            password: password,
            finderRequest: nil
        )
    }

    func createEncryptedArchiveFromFinder(_ sourceURLs: [URL]) {
        guard beginUserFlow() else { return }
        let request: FinderArchiveRequest
        do {
            request = try FinderArchiveRequest(sourceURLs: sourceURLs)
        } catch {
            isBusy = false
            presentErrorMessage("Finder 没有提供可压缩的文件或文件夹。")
            return
        }
        guard let choice = PasswordPrompt.requestNewPassword(for: request) else {
            isBusy = false
            return
        }
        startEncryptedCreation(
            sourceURLs: choice.request.sourceURLs,
            destination: choice.request.destinationURL,
            password: choice.password,
            finderRequest: choice.request
        )
    }

    private func startEncryptedCreation(
        sourceURLs: [URL],
        destination: URL,
        password: String,
        finderRequest: FinderArchiveRequest?
    ) {
        progress.show(title: "正在创建加密 ZIP", detail: destination.lastPathComponent)
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                do {
                    if let finderRequest {
                        _ = try FinderEncryptedArchiveCreator.create(
                            request: finderRequest,
                            password: password
                        )
                    } else {
                        try ZipArchive.create(
                            at: destination,
                            contentsOf: sourceURLs,
                            encryption: .winZipAES256(password: password)
                        )
                    }
                    return WorkflowOutcome.success
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
            isBusy = false
            progress.dismiss()
            handleCompletion(
                outcome,
                successTitle: "ZIP 已创建",
                successMessage: destination.path,
                reveal: destination
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
            isBusy = false
            return
        }

        progress.show(title: "正在读取 ZIP", detail: archive.lastPathComponent)
        Task {
            let listing = await Task.detached(priority: .userInitiated) {
                do {
                    return ListingOutcome.success(try ZipArchive.list(archive))
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
            case .zipFailure(let error):
                isBusy = false
                presentError(error)
                return
            case .systemFailure(let message):
                isBusy = false
                presentErrorMessage(message)
                return
            }

            guard !entries.isEmpty else {
                isBusy = false
                presentErrorMessage("这个 ZIP 中没有可解压的内容。")
                return
            }

            let password: String?
            if entries.contains(where: \.isEncrypted) {
                guard let supplied = PasswordPrompt.requestExistingPassword() else {
                    isBusy = false
                    return
                }
                password = supplied
            } else {
                password = nil
            }

            let destinationPanel = NSOpenPanel()
            destinationPanel.title = "选择解压位置"
            destinationPanel.prompt = "解压到这里"
            destinationPanel.canChooseFiles = false
            destinationPanel.canChooseDirectories = true
            destinationPanel.canCreateDirectories = true
            destinationPanel.allowsMultipleSelection = false
            destinationPanel.directoryURL = archive.deletingLastPathComponent()
            guard destinationPanel.runModal() == .OK, let parent = destinationPanel.url else {
                isBusy = false
                return
            }

            let destination = uniqueExtractionDestination(
                below: parent,
                preferredName: archive.deletingPathExtension().lastPathComponent
            )
            progress.show(title: "正在解压 ZIP", detail: archive.lastPathComponent)
            let outcome = await Task.detached(priority: .userInitiated) {
                do {
                    try ZipArchive.extract(archive, to: destination, password: password)
                    return WorkflowOutcome.success
                } catch let error as ZipError {
                    return WorkflowOutcome.zipFailure(error)
                } catch {
                    return WorkflowOutcome.systemFailure(error.localizedDescription)
                }
            }.value
            isBusy = false
            progress.dismiss()
            handleCompletion(
                outcome,
                successTitle: "ZIP 已解压",
                successMessage: destination.path,
                reveal: destination
            )
        }
    }

    func showHelp() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "aulycZip 使用说明"
        alert.informativeText = """
        创建加密 ZIP：使用 WinZip AES-256（AE-2）加密文件内容，可与 WinZip、7-Zip、Keka 互操作。

        ZIP 标准不会隐藏文件名：即使内容已加密，打开压缩包仍可能看到其中的文件和目录名称。若名称也敏感，可先用 Finder 自带功能压缩成一个普通 ZIP，再将这个 ZIP 作为单个文件加密压缩。

        密码不会保存，也不会写入日志。忘记密码后无法恢复。
        """
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    func showAbout() {
        aboutWindowController.show()
    }

    private func beginUserFlow() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        guard !isBusy else {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "已有任务正在进行"
            alert.informativeText = "请等待当前压缩或解压任务完成。"
            alert.runModal()
            return false
        }
        isBusy = true
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

    private func uniqueExtractionDestination(below parent: URL, preferredName: String) -> URL {
        let baseName = preferredName.isEmpty ? "解压内容" : preferredName
        var candidate = parent.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(baseName) \(suffix)", isDirectory: true)
            suffix += 1
        }
        return candidate
    }

    private func handleCompletion(
        _ outcome: WorkflowOutcome,
        successTitle: String,
        successMessage: String,
        reveal: URL
    ) {
        switch outcome {
        case .success:
            let alert = NSAlert()
            alert.messageText = successTitle
            alert.informativeText = successMessage
            alert.addButton(withTitle: "在 Finder 中显示")
            alert.addButton(withTitle: "完成")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([reveal])
            }
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
        case .unsupportedFeature(let reason):
            message = "暂不支持这个 ZIP：\(reason)"
        case .invalidArchive(let reason):
            message = "ZIP 格式无效：\(reason)"
        case .truncatedArchive:
            message = "ZIP 数据不完整，文件可能已损坏。"
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
