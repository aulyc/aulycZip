import AppKit
import OSLog
import aulycZipAppSupport

@MainActor
final class UpdateController {
    private static let logger = Logger(
        subsystem: "com.aulyc.aulyczip",
        category: "updater"
    )

    private let manifestLoader: UpdateManifestLoader
    private let progressPanel = UpdateProgressPanelController()
    private let lastCheckKey = "aulycZip.lastUpdateCheckAt"
    private var isBusy = false
    private var latestManifest: UpdateManifest?

    init() {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.0.0"
        manifestLoader = UpdateManifestLoader {
            "aulycZip/\(version)"
        }
    }

    func scheduleAutomaticCheckIfDue() {
        guard Bundle.main.object(forInfoDictionaryKey: "AulycZipReleaseChannel") as? String
                == "formal",
              isAutomaticCheckDue
        else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.isAutomaticCheckDue, !self.isBusy else { return }
            self.check(manual: false)
        }
    }

    func checkManually() {
        check(manual: true)
    }

    private var isAutomaticCheckDue: Bool {
        guard let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date else {
            return true
        }
        return Date().timeIntervalSince(lastCheck) >= 24 * 60 * 60
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.0.0"
    }

    private var currentBuildNumber: Int {
        let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
        return Int(String(describing: value ?? "0")) ?? 0
    }

    private func check(manual: Bool) {
        guard !isBusy else {
            if manual {
                showMessage(title: "正在检查更新", message: "请等待当前更新操作完成")
            }
            return
        }
        isBusy = true

        manifestLoader.load { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isBusy = false
                UserDefaults.standard.set(Date(), forKey: self.lastCheckKey)

                switch result {
                case .failure(let error):
                    Self.logFailure(stage: "manifest", error: error)
                    if manual {
                        self.showMessage(
                            title: "无法检查更新",
                            message: "GitHub 和 Gitee 更新源当前都不可用，请稍后再试"
                        )
                    }
                case .success(let loaded):
                    let manifest = loaded.manifest
                    guard UpdateVersion.isNewer(
                        version: manifest.version,
                        buildNumber: manifest.buildNumber,
                        thanVersion: self.currentVersion,
                        buildNumber: self.currentBuildNumber
                    ) else {
                        self.latestManifest = nil
                        if manual {
                            self.showMessage(
                                title: "已是最新版本",
                                message: "当前版本为 \(self.currentVersion)（build \(self.currentBuildNumber)）"
                            )
                        }
                        return
                    }

                    self.latestManifest = manifest
                    self.presentAvailableUpdate(manifest)
                }
            }
        }
    }

    private func presentAvailableUpdate(_ manifest: UpdateManifest) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "发现 aulycZip \(manifest.version)"
        alert.informativeText = "新版本将从 GitHub 优先下载；连接或校验失败时自动切换到 Gitee，并在安装前验证发布溯源、SHA-256、签名和公证"
        alert.addButton(withTitle: "立即更新")
        alert.addButton(withTitle: "稍后")
        alert.addButton(withTitle: "查看发布页")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            beginInstall(manifest)
        case .alertThirdButtonReturn:
            NSWorkspace.shared.open(manifest.releasePageURL)
        default:
            break
        }
    }

    private func beginInstall(_ manifest: UpdateManifest) {
        do {
            try UpdateInstaller.validateCurrentInstallLocation()
        } catch {
            showInstallFailure(error, releasePageURL: manifest.releasePageURL)
            return
        }
        guard !isBusy else { return }
        isBusy = true
        UpdateInstaller.cleanStaleArtifacts()
        progressPanel.show(message: "正在验证发布信息")

        UpdateInstaller.shared.downloadProvenance(
            from: manifest.orderedProvenanceURLs,
            expectedSHA256: manifest.provenance.sha256
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.finishWithFailure(
                    stage: "provenance-download",
                    error: error,
                    releasePageURL: manifest.releasePageURL
                )
            case .success(let provenanceURL):
                self.downloadDMG(manifest, provenanceURL: provenanceURL)
            }
        }
    }

    private func downloadDMG(_ manifest: UpdateManifest, provenanceURL: URL) {
        progressPanel.update(message: "正在下载安装包", fraction: 0)
        var lastPercent = -1
        UpdateInstaller.shared.downloadDMG(
            from: manifest.orderedDownloadURLs,
            expectedSHA256: manifest.artifact.sha256,
            progress: { [weak self] fraction in
                let percent = Int(fraction * 100)
                guard percent != lastPercent else { return }
                lastPercent = percent
                self?.progressPanel.update(
                    message: "正在下载安装包（\(percent)%）",
                    fraction: fraction
                )
            },
            completion: { [weak self] result in
                guard let self else { return }
                switch result {
                case .failure(let error):
                    try? FileManager.default.removeItem(at: provenanceURL)
                    self.finishWithFailure(
                        stage: "artifact-download",
                        error: error,
                        releasePageURL: manifest.releasePageURL
                    )
                case .success(let dmgURL):
                    self.prepareAndActivate(
                        manifest,
                        provenanceURL: provenanceURL,
                        dmgURL: dmgURL
                    )
                }
            }
        )
    }

    private func prepareAndActivate(
        _ manifest: UpdateManifest,
        provenanceURL: URL,
        dmgURL: URL
    ) {
        progressPanel.update(message: "正在验证签名与公证", fraction: nil)
        Task { [weak self] in
            guard let self else { return }
            do {
                let prepared = try await Task.detached(priority: .userInitiated) {
                    try UpdateInstaller.prepareUpdate(
                        dmgAt: dmgURL,
                        provenanceAt: provenanceURL,
                        manifest: manifest,
                        phase: { phase in
                            Task { @MainActor [weak self] in
                                let message: String
                                switch phase {
                                case .verifying: message = "正在验证签名与公证"
                                case .extracting: message = "正在检查安装包中的应用"
                                case .ready: message = "验证完成，正在准备替换"
                                }
                                self?.progressPanel.update(message: message, fraction: nil)
                            }
                        }
                    )
                }.value
                try UpdateInstaller.activatePreparedUpdate(prepared)
                self.progressPanel.update(message: "即将重新启动 aulycZip", fraction: nil)
                NSApp.terminate(nil)
            } catch {
                self.finishWithFailure(
                    stage: "verification-install",
                    error: error,
                    releasePageURL: manifest.releasePageURL
                )
            }
        }
    }

    private func finishWithFailure(stage: String, error: Error, releasePageURL: URL) {
        isBusy = false
        progressPanel.close()
        Self.logFailure(stage: stage, error: error)
        showInstallFailure(error, releasePageURL: releasePageURL)
    }

    private func showInstallFailure(_ error: Error, releasePageURL: URL) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "无法自动安装更新"
        alert.informativeText = (error as? LocalizedError)?.errorDescription
            ?? "更新验证或安装失败，当前应用没有被替换"
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "打开发布页")
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.open(releasePageURL)
        }
    }

    private func showMessage(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private static func logFailure(stage: String, error: Error) {
        let code: String
        if let installError = error as? UpdateInstaller.InstallError {
            code = "installer.\(installError.rawValue)"
        } else if let manifestError = error as? UpdateManifest.ValidationError {
            code = "manifest.\(manifestError.rawValue)"
        } else {
            let systemError = error as NSError
            code = "system.\(systemError.domain).\(systemError.code)"
        }
        logger.error(
            "Update failed stage=\(stage, privacy: .public) code=\(code, privacy: .public)"
        )
    }
}
