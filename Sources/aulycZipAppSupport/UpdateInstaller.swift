import CryptoKit
import Foundation

public enum InstallPhase: Equatable, Sendable {
    case verifying
    case extracting
    case ready
}

public final class PreparedUpdate: @unchecked Sendable {
    fileprivate let workDirectory: URL
    fileprivate let replacementApp: URL
    fileprivate var handedOff = false

    fileprivate init(workDirectory: URL, replacementApp: URL) {
        self.workDirectory = workDirectory
        self.replacementApp = replacementApp
    }

    deinit {
        if !handedOff {
            try? FileManager.default.removeItem(at: workDirectory)
        }
    }
}

/// Downloads and verifies the exact formal release before handing an app swap
/// to a detached helper. Mutable URLSession state has one serial owner.
public final class UpdateInstaller: NSObject, @unchecked Sendable {
    public static let shared = UpdateInstaller()

    public enum InstallError: String, Error, Equatable, LocalizedError, Sendable {
        case download
        case checksumMismatch
        case invalidManifest
        case invalidProvenance
        case mountFailed
        case bundleNotFound
        case identityMismatch
        case signatureInvalid
        case unsupportedInstallLocation
        case notWritable
        case helperLaunchFailed

        public var errorDescription: String? {
            switch self {
            case .download: return "更新文件下载失败"
            case .checksumMismatch: return "更新文件完整性校验失败"
            case .invalidManifest: return "更新清单验证失败"
            case .invalidProvenance: return "发布溯源验证失败"
            case .mountFailed: return "更新安装包无法打开"
            case .bundleNotFound: return "安装包中没有找到 aulycZip"
            case .identityMismatch: return "更新应用的版本或产品身份不匹配"
            case .signatureInvalid: return "更新应用的签名或公证验证失败"
            case .unsupportedInstallLocation: return "仅支持升级 /Applications 中的 aulycZip"
            case .notWritable: return "当前用户无法替换已安装的 aulycZip"
            case .helperLaunchFailed: return "更新替换程序无法启动"
            }
        }
    }

    private var session: URLSession?
    private var progressHandler: (@MainActor @Sendable (Double) -> Void)?
    private var finishHandler: (@MainActor @Sendable (Result<URL, Error>) -> Void)?
    private var downloadURLs: [URL] = []
    private var downloadIndex = 0
    private var expectedSHA256 = ""
    private var activeTaskIdentifier: Int?
    private var handledTaskIdentifiers = Set<Int>()
    private var delivered = false
    private let makeSessionConfiguration: @Sendable () -> URLSessionConfiguration
    private let stateQueue = DispatchQueue(label: "com.aulyc.aulyczip.update-installer")

    private override init() {
        makeSessionConfiguration = { .default }
        super.init()
    }

    public init(sessionConfiguration: URLSessionConfiguration) {
        makeSessionConfiguration = {
            sessionConfiguration.copy() as! URLSessionConfiguration
        }
        super.init()
    }

    public func downloadDMG(
        from urls: [URL],
        expectedSHA256: String,
        progress: @escaping @MainActor @Sendable (Double) -> Void,
        completion: @escaping @MainActor @Sendable (Result<URL, Error>) -> Void
    ) {
        downloadVerifiedFile(
            from: urls,
            expectedSHA256: expectedSHA256,
            progress: progress,
            completion: completion
        )
    }

    public func downloadProvenance(
        from urls: [URL],
        expectedSHA256: String,
        completion: @escaping @MainActor @Sendable (Result<URL, Error>) -> Void
    ) {
        downloadVerifiedFile(
            from: urls,
            expectedSHA256: expectedSHA256,
            progress: { _ in },
            completion: completion
        )
    }

    private func downloadVerifiedFile(
        from urls: [URL],
        expectedSHA256: String,
        progress: @escaping @MainActor @Sendable (Double) -> Void,
        completion: @escaping @MainActor @Sendable (Result<URL, Error>) -> Void
    ) {
        guard !urls.isEmpty, UpdateManifest.isSHA256(expectedSHA256) else {
            Task { @MainActor in completion(.failure(InstallError.download)) }
            return
        }

        stateQueue.async { [self] in
            downloadURLs = urls
            downloadIndex = 0
            self.expectedSHA256 = expectedSHA256
            progressHandler = progress
            finishHandler = completion
            activeTaskIdentifier = nil
            handledTaskIdentifiers.removeAll()
            delivered = false

            let configuration = makeSessionConfiguration()
            configuration.timeoutIntervalForResource = 300
            let session = URLSession(
                configuration: configuration,
                delegate: self,
                delegateQueue: nil
            )
            self.session = session
            startCurrentDownload()
        }
    }

    private func startCurrentDownload() {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        guard downloadURLs.indices.contains(downloadIndex), let session else {
            deliver(.failure(InstallError.download))
            return
        }
        let progressHandler = progressHandler
        Task { @MainActor in progressHandler?(0) }
        var request = URLRequest(
            url: downloadURLs[downloadIndex],
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 60
        )
        request.setValue("aulycZip", forHTTPHeaderField: "User-Agent")
        let task = session.downloadTask(with: request)
        activeTaskIdentifier = task.taskIdentifier
        task.resume()
    }

    private func retryDownload(after error: Error) {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        guard !delivered else { return }
        downloadIndex += 1
        guard downloadURLs.indices.contains(downloadIndex) else {
            deliver(.failure(error))
            return
        }
        startCurrentDownload()
    }

    private func deliver(_ result: Result<URL, Error>) {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        guard !delivered else { return }
        delivered = true
        let handler = finishHandler
        finishHandler = nil
        progressHandler = nil
        downloadURLs = []
        activeTaskIdentifier = nil
        session?.finishTasksAndInvalidate()
        session = nil
        Task { @MainActor in handler?(result) }
    }

    public static func validateCurrentInstallLocation(
        bundleURL: URL = Bundle.main.bundleURL
    ) throws {
        let expected = URL(
            fileURLWithPath: "/Applications/aulycZip.app",
            isDirectory: true
        ).standardizedFileURL
        guard bundleURL.standardizedFileURL.path == expected.path else {
            throw InstallError.unsupportedInstallLocation
        }
        let parent = expected.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw InstallError.notWritable
        }
    }

    /// Verifies provenance, DMG trust, the mounted App, and all embedded release
    /// identity before returning an isolated replacement bundle.
    public static func prepareUpdate(
        dmgAt dmgURL: URL,
        provenanceAt provenanceURL: URL,
        manifest: UpdateManifest,
        phase: @escaping @Sendable (InstallPhase) -> Void
    ) throws -> PreparedUpdate {
        do {
            try manifest.validate()
        } catch {
            throw InstallError.invalidManifest
        }
        try verifyProvenance(at: provenanceURL, manifest: manifest)
        phase(.verifying)
        guard try sha256(of: dmgURL) == manifest.artifact.sha256 else {
            throw InstallError.checksumMismatch
        }
        try verifyFormalDMG(at: dmgURL)

        phase(.extracting)
        let fileManager = FileManager.default
        let workDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("aulycZip-update-\(UUID().uuidString)", isDirectory: true)
        let mountPoint = workDirectory.appendingPathComponent("mount", isDirectory: true)
        let replacementDirectory = workDirectory
            .appendingPathComponent("replacement", isDirectory: true)
        var mounted = false
        var completed = false
        defer {
            if mounted {
                try? runProcess(
                    "/usr/bin/hdiutil",
                    ["detach", mountPoint.path],
                    throwing: .mountFailed
                )
            }
            if !completed {
                try? fileManager.removeItem(at: workDirectory)
            }
            try? fileManager.removeItem(at: dmgURL)
            try? fileManager.removeItem(at: provenanceURL)
        }

        try fileManager.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: replacementDirectory,
            withIntermediateDirectories: true
        )
        try runProcess(
            "/usr/bin/hdiutil",
            ["attach", dmgURL.path, "-nobrowse", "-readonly", "-mountpoint", mountPoint.path],
            throwing: .mountFailed
        )
        mounted = true

        let mountedApp = mountPoint.appendingPathComponent("aulycZip.app", isDirectory: true)
        guard fileManager.fileExists(atPath: mountedApp.path) else {
            throw InstallError.bundleNotFound
        }
        let replacementApp = replacementDirectory
            .appendingPathComponent("aulycZip.app", isDirectory: true)
        try runProcess(
            "/usr/bin/ditto",
            [mountedApp.path, replacementApp.path],
            throwing: .bundleNotFound
        )
        try runProcess(
            "/usr/bin/hdiutil",
            ["detach", mountPoint.path],
            throwing: .mountFailed
        )
        mounted = false

        try verifyApplication(
            at: replacementApp,
            manifest: manifest,
            provenanceAt: provenanceURL
        )
        phase(.ready)
        completed = true
        return PreparedUpdate(
            workDirectory: workDirectory,
            replacementApp: replacementApp
        )
    }

    /// Starts the fixed-path replacement helper. The caller must terminate the
    /// current process immediately after this returns.
    public static func activatePreparedUpdate(_ prepared: PreparedUpdate) throws {
        try validateCurrentInstallLocation()
        let destination = URL(
            fileURLWithPath: "/Applications/aulycZip.app",
            isDirectory: true
        )
        let pid = ProcessInfo.processInfo.processIdentifier
        let backup = URL(
            fileURLWithPath: "/Applications/.aulycZip-update-backup-\(pid).app",
            isDirectory: true
        )
        let script = try replacementScript(
            sourceApp: prepared.replacementApp,
            destinationApp: destination,
            backupApp: backup,
            currentPID: pid
        )

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [
            "-c", script, "aulycZip-updater",
            prepared.replacementApp.path, destination.path, backup.path,
        ]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            throw InstallError.helperLaunchFailed
        }
        prepared.handedOff = true
    }

    static func replacementScript(
        sourceApp: URL,
        destinationApp: URL,
        backupApp: URL,
        currentPID: Int32
    ) throws -> String {
        let canonicalDestination = URL(
            fileURLWithPath: "/Applications/aulycZip.app",
            isDirectory: true
        ).standardizedFileURL
        let expectedBackup = URL(
            fileURLWithPath: "/Applications/.aulycZip-update-backup-\(currentPID).app",
            isDirectory: true
        ).standardizedFileURL
        let sourceParent = sourceApp.standardizedFileURL.deletingLastPathComponent()
        let workDirectory = sourceParent.deletingLastPathComponent()
        guard destinationApp.standardizedFileURL.path == canonicalDestination.path,
              backupApp.standardizedFileURL.path == expectedBackup.path,
              sourceApp.lastPathComponent == "aulycZip.app",
              sourceParent.lastPathComponent == "replacement",
              workDirectory.lastPathComponent.hasPrefix("aulycZip-update-"),
              currentPID > 0
        else {
            throw InstallError.unsupportedInstallLocation
        }

        return """
        source_app="$1"
        destination_app="$2"
        backup_app="$3"
        [ "$destination_app" = "/Applications/aulycZip.app" ] || exit 21
        [ -d "$source_app" ] || exit 22
        [ ! -e "$backup_app" ] || exit 23
        attempt=0
        while kill -0 \(currentPID) 2>/dev/null; do
          attempt=$((attempt + 1))
          [ "$attempt" -ge 150 ] && exit 20
          /bin/sleep 0.1
        done
        kill -0 \(currentPID) 2>/dev/null && exit 20
        /bin/mv "$destination_app" "$backup_app" || exit 24
        if /bin/mv "$source_app" "$destination_app"; then
          /bin/rm -rf "$backup_app"
          work_dir="$(/usr/bin/dirname "$(/usr/bin/dirname "$source_app")")"
          case "$(/usr/bin/basename "$work_dir")" in
            aulycZip-update-*) /bin/rm -rf "$work_dir" ;;
            *) exit 27 ;;
          esac
          /usr/bin/open "$destination_app"
          exit 0
        fi
        [ ! -e "$destination_app" ] || /bin/rm -rf "$destination_app"
        /bin/mv "$backup_app" "$destination_app" || exit 25
        /usr/bin/open "$destination_app"
        exit 26
        """
    }

    public static func cleanStaleArtifacts() {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: fileManager.temporaryDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        for entry in entries where entry.lastPathComponent.hasPrefix("aulycZip-update-") {
            try? fileManager.removeItem(at: entry)
        }
    }

    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            digest.update(data: data)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func verifyProvenance(at url: URL, manifest: UpdateManifest) throws {
        guard let data = try? Data(contentsOf: url) else {
            throw InstallError.invalidProvenance
        }
        try verifyProvenanceData(data, manifest: manifest)
    }

    public static func verifyProvenanceData(
        _ data: Data,
        manifest: UpdateManifest
    ) throws {
        guard let raw = try? JSONSerialization.jsonObject(with: data),
              let value = raw as? [String: Any]
        else {
            throw InstallError.invalidProvenance
        }
        let requiredKeys: Set<String> = [
            "$schema", "project", "releaseProfile", "releaseChannel", "version",
            "buildNumber", "tag", "commit", "dirty", "builtAt", "artifacts",
            "architecture", "bundleIdentifier", "bundleName", "executableName",
            "minimumSystemVersion", "signatureType", "teamIdentifier", "hardenedRuntime",
            "entitlements", "notarized", "notarizationSubmissionId",
            "appExecutableSha256", "infoPlistSha256", "sourceRepository", "sourceBranch",
            "sourceRemoteCommit", "sourceRemoteTagCommit", "sourceRemoteVerifiedAt",
        ]
        guard Set(value.keys) == requiredKeys,
              value["$schema"] as? String == "urn:aulyc:release-provenance:1",
              value["project"] as? String == "aulycZip",
              value["releaseProfile"] as? String == manifest.releaseProfile,
              value["releaseChannel"] as? String == "formal",
              value["version"] as? String == manifest.version,
              value["buildNumber"] as? Int == manifest.buildNumber,
              value["tag"] as? String == manifest.tag,
              value["commit"] as? String == manifest.commit,
              value["dirty"] as? Bool == false,
              value["architecture"] as? String == "arm64",
              value["bundleIdentifier"] as? String == manifest.bundleIdentifier,
              value["bundleName"] as? String == "aulycZip",
              value["executableName"] as? String == "aulycZip",
              value["minimumSystemVersion"] as? String == manifest.minimumSystemVersion,
              value["signatureType"] as? String == "developer-id",
              value["teamIdentifier"] as? String == manifest.teamIdentifier,
              value["hardenedRuntime"] as? Bool == true,
              let entitlements = value["entitlements"] as? [String: Any],
              entitlements.isEmpty,
              value["notarized"] as? Bool == true,
              let submissionID = value["notarizationSubmissionId"] as? String,
              !submissionID.isEmpty,
              let executableHash = value["appExecutableSha256"] as? String,
              UpdateManifest.isSHA256(executableHash),
              let infoHash = value["infoPlistSha256"] as? String,
              UpdateManifest.isSHA256(infoHash),
              value["sourceRepository"] as? String == UpdateManifest.sourceRepository,
              value["sourceBranch"] as? String == UpdateManifest.sourceBranch,
              value["sourceRemoteCommit"] as? String == manifest.commit,
              value["sourceRemoteTagCommit"] as? String == manifest.commit,
              let builtAt = value["builtAt"] as? String,
              isUTCDate(builtAt),
              let verifiedAt = value["sourceRemoteVerifiedAt"] as? String,
              isUTCDate(verifiedAt),
              let artifacts = value["artifacts"] as? [[String: Any]],
              artifacts.count == 1,
              Set(artifacts[0].keys) == ["file", "sha256"],
              artifacts[0]["file"] as? String == manifest.artifact.file,
              artifacts[0]["sha256"] as? String == manifest.artifact.sha256
        else {
            throw InstallError.invalidProvenance
        }
    }

    private static func isUTCDate(_ value: String) -> Bool {
        value.hasSuffix("Z") && ISO8601DateFormatter().date(from: value) != nil
    }

    private static func verifyFormalDMG(at dmg: URL) throws {
        try runProcess(
            "/usr/bin/codesign",
            ["--verify", "--verbose=2", dmg.path],
            throwing: .signatureInvalid
        )
        try runProcess(
            "/usr/bin/xcrun",
            ["stapler", "validate", dmg.path],
            throwing: .signatureInvalid
        )
        try runProcess(
            "/usr/sbin/spctl",
            ["-a", "-vvv", "-t", "open", "--context", "context:primary-signature", dmg.path],
            throwing: .signatureInvalid
        )
    }

    private static func verifyApplication(
        at app: URL,
        manifest: UpdateManifest,
        provenanceAt provenanceURL: URL
    ) throws {
        guard let provenanceData = try? Data(contentsOf: provenanceURL),
              let raw = try? JSONSerialization.jsonObject(with: provenanceData),
              let provenance = raw as? [String: Any],
              let expectedExecutableHash = provenance["appExecutableSha256"] as? String,
              let expectedInfoHash = provenance["infoPlistSha256"] as? String
        else {
            throw InstallError.invalidProvenance
        }

        let infoURL = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let propertyList = try? PropertyListSerialization.propertyList(
                from: data,
                format: nil
              ),
              let info = propertyList as? [String: Any],
              info["CFBundleIdentifier"] as? String == manifest.bundleIdentifier,
              info["CFBundleName"] as? String == "aulycZip",
              info["CFBundleExecutable"] as? String == "aulycZip",
              info["CFBundleShortVersionString"] as? String == manifest.version,
              String(describing: info["CFBundleVersion"] ?? "") == String(manifest.buildNumber),
              info["LSMinimumSystemVersion"] as? String == manifest.minimumSystemVersion,
              info["AulycZipGitCommit"] as? String == manifest.commit,
              info["AulycZipReleaseChannel"] as? String == "formal",
              info["AulycZipReleaseTag"] as? String == manifest.tag,
              info["AulycZipBuildDirty"] as? Bool == false
        else {
            throw InstallError.identityMismatch
        }

        let executable = app.appendingPathComponent("Contents/MacOS/aulycZip")
        guard FileManager.default.fileExists(atPath: executable.path),
              try sha256(of: executable) == expectedExecutableHash,
              try sha256(of: infoURL) == expectedInfoHash
        else {
            throw InstallError.identityMismatch
        }

        try runProcess(
            "/usr/bin/codesign",
            ["--verify", "--deep", "--strict", "--verbose=2", app.path],
            throwing: .signatureInvalid
        )
        let signature = try capturedOutput(
            "/usr/bin/codesign",
            ["-dv", "--verbose=4", app.path],
            throwing: .signatureInvalid
        )
        guard signature.contains("Authority=Developer ID Application:"),
              signature.contains("TeamIdentifier=\(manifest.teamIdentifier)"),
              signature.contains("(runtime)")
        else {
            throw InstallError.signatureInvalid
        }
        let entitlements = try capturedOutput(
            "/usr/bin/codesign",
            ["-d", "--entitlements", ":-", app.path],
            throwing: .signatureInvalid
        )
        guard !entitlements.contains("<key>") else {
            throw InstallError.signatureInvalid
        }
        guard try capturedOutput(
            "/usr/bin/lipo",
            ["-archs", executable.path],
            throwing: .identityMismatch
        ) == "arm64" else {
            throw InstallError.identityMismatch
        }
        try runProcess(
            "/usr/sbin/spctl",
            ["-a", "-vvv", "-t", "exec", app.path],
            throwing: .signatureInvalid
        )
    }

    private static func preserveDownloadedFile(
        at location: URL,
        pathExtension: String?
    ) throws -> URL {
        guard let pathExtension, ["dmg", "json"].contains(pathExtension) else {
            throw InstallError.download
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("aulycZip-update-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
        try FileManager.default.moveItem(at: location, to: destination)
        return destination
    }

    private static func runProcess(
        _ launchPath: String,
        _ arguments: [String],
        throwing error: InstallError
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw error
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw error }
    }

    private static func capturedOutput(
        _ launchPath: String,
        _ arguments: [String],
        throwing error: InstallError
    ) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            throw error
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw error }
        return String(
            decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension UpdateInstaller: URLSessionDownloadDelegate {
    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let sessionID = ObjectIdentifier(session)
        stateQueue.async { [self] in
            guard let activeSession = self.session,
                  ObjectIdentifier(activeSession) == sessionID,
                  totalBytesExpectedToWrite > 0
            else { return }
            let fraction = min(
                max(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 0),
                1
            )
            let handler = progressHandler
            Task { @MainActor in handler?(fraction) }
        }
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let sessionID = ObjectIdentifier(session)
        let taskIdentifier = downloadTask.taskIdentifier
        let statusCode = (downloadTask.response as? HTTPURLResponse)?.statusCode
        let preserved: Result<URL, Error>
        if statusCode == nil || statusCode == 200 {
            let pathExtension = downloadTask.originalRequest?.url?.pathExtension.lowercased()
            preserved = Result {
                try Self.preserveDownloadedFile(
                    at: location,
                    pathExtension: pathExtension
                )
            }
        } else {
            preserved = .failure(InstallError.download)
        }

        stateQueue.async { [self] in
            guard let activeSession = self.session,
                  ObjectIdentifier(activeSession) == sessionID,
                  taskIdentifier == activeTaskIdentifier,
                  !delivered
            else {
                if case .success(let url) = preserved {
                    try? FileManager.default.removeItem(at: url)
                }
                return
            }
            handledTaskIdentifiers.insert(taskIdentifier)
            switch preserved {
            case .failure(let error):
                retryDownload(after: error)
            case .success(let url):
                do {
                    guard try Self.sha256(of: url) == expectedSHA256 else {
                        try? FileManager.default.removeItem(at: url)
                        retryDownload(after: InstallError.checksumMismatch)
                        return
                    }
                    deliver(.success(url))
                } catch {
                    try? FileManager.default.removeItem(at: url)
                    retryDownload(after: error)
                }
            }
        }
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        let sessionID = ObjectIdentifier(session)
        let taskIdentifier = task.taskIdentifier
        stateQueue.async { [self] in
            guard let activeSession = self.session,
                  ObjectIdentifier(activeSession) == sessionID,
                  taskIdentifier == activeTaskIdentifier,
                  !handledTaskIdentifiers.contains(taskIdentifier),
                  !delivered
            else { return }
            handledTaskIdentifiers.insert(taskIdentifier)
            retryDownload(after: error ?? InstallError.download)
        }
    }
}
