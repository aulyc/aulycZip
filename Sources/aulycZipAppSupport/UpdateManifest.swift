import Foundation

/// The immutable formal-release identity published by both update mirrors.
///
/// Network transport may fall back from GitHub to Gitee, but the document,
/// download order, product identity, and verification requirements are fixed.
public struct UpdateManifest: Decodable, Equatable, Sendable {
    public enum Source: String, CaseIterable, Decodable, Sendable {
        case github
        case gitee
    }

    public struct Download: Decodable, Equatable, Sendable {
        public let source: Source
        public let url: URL
    }

    public struct FileRecord: Decodable, Equatable, Sendable {
        public let file: String
        public let sha256: String
        public let downloads: [Download]
    }

    public enum ValidationError: String, Error, Equatable, LocalizedError, Sendable {
        case malformedDocument
        case unsupportedSchema
        case unknownFields
        case unexpectedReleaseIdentity
        case invalidVersion
        case invalidBuild
        case invalidCommit
        case invalidArtifact
        case invalidDownloadSources
        case insecureURL

        public var errorDescription: String? {
            switch self {
            case .malformedDocument: return "更新清单不是有效的 JSON 文档"
            case .unsupportedSchema: return "更新清单版本不受支持"
            case .unknownFields: return "更新清单包含缺失或未知字段"
            case .unexpectedReleaseIdentity: return "更新清单的产品或发布身份不匹配"
            case .invalidVersion: return "更新清单的版本号无效"
            case .invalidBuild: return "更新清单的构建号无效"
            case .invalidCommit: return "更新清单的提交身份无效"
            case .invalidArtifact: return "更新清单的文件身份或校验值无效"
            case .invalidDownloadSources: return "更新镜像必须按 GitHub、Gitee 顺序完整提供"
            case .insecureURL: return "更新清单包含不受信任的下载地址"
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schema = "$schema"
        case schemaVersion
        case policy
        case releaseProfile
        case releaseChannel
        case version
        case buildNumber
        case tag
        case commit
        case bundleIdentifier
        case pluginIdentifier
        case architecture
        case teamIdentifier
        case minimumSystemVersion
        case releasePageURL
        case artifact
        case provenance
    }

    public static let expectedSchema = "urn:codex-engineering-standards:dual-mirror-latest:2"
    public static let expectedBundleIdentifier = "com.aulyc.aulyczip"
    public static let expectedTeamIdentifier = "M9M7M2ARFD"
    public static let expectedMinimumSystemVersion = "14.0"
    public static let sourceRepository = "aulyc/aulycZip"
    public static let sourceBranch = "main"
    public static let githubUpdateBranch = "release-channel"
    public static let giteeUpdateBranch = "main"

    public let schema: String
    public let schemaVersion: Int
    public let policy: String
    public let releaseProfile: String
    public let releaseChannel: String
    public let version: String
    public let buildNumber: Int
    public let tag: String
    public let commit: String
    public let bundleIdentifier: String
    public let pluginIdentifier: String?
    public let architecture: String
    public let teamIdentifier: String
    public let minimumSystemVersion: String
    public let releasePageURL: URL
    public let artifact: FileRecord
    public let provenance: FileRecord

    public static func decodeValidated(from data: Data) throws -> UpdateManifest {
        try validateExactShape(data)
        let manifest: UpdateManifest
        do {
            manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
        } catch {
            throw ValidationError.malformedDocument
        }
        try manifest.validate()
        return manifest
    }

    public func validate() throws {
        guard schema == Self.expectedSchema, schemaVersion == 2 else {
            throw ValidationError.unsupportedSchema
        }
        guard policy == "aulyc-dual-mirror-v1",
              releaseProfile == "macos-arm64-app",
              releaseChannel == "formal",
              bundleIdentifier == Self.expectedBundleIdentifier,
              pluginIdentifier == nil,
              architecture == "arm64",
              teamIdentifier == Self.expectedTeamIdentifier,
              minimumSystemVersion == Self.expectedMinimumSystemVersion,
              tag == version
        else {
            throw ValidationError.unexpectedReleaseIdentity
        }
        guard Self.isStableVersion(version) else {
            throw ValidationError.invalidVersion
        }
        guard buildNumber > 0 else {
            throw ValidationError.invalidBuild
        }
        guard Self.isCommit(commit) else {
            throw ValidationError.invalidCommit
        }

        let stem = "aulycZip-\(version)-build.\(buildNumber)-formal-macos-arm64"
        guard artifact.file == "\(stem).dmg",
              provenance.file == "\(stem).release-provenance.json",
              Self.isSHA256(artifact.sha256),
              Self.isSHA256(provenance.sha256)
        else {
            throw ValidationError.invalidArtifact
        }

        try validateReleasePage()
        try validateDownloads(artifact, kind: .release)
        try validateDownloads(provenance, kind: .rawProvenance)
    }

    public var orderedDownloadURLs: [URL] { artifact.downloads.map(\.url) }
    public var orderedProvenanceURLs: [URL] { provenance.downloads.map(\.url) }

    public static func isStableVersion(_ value: String) -> Bool {
        matches(value, #"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$"#)
    }

    public static func isSHA256(_ value: String) -> Bool {
        matches(value, #"^[0-9a-f]{64}$"#)
    }

    public static func isCommit(_ value: String) -> Bool {
        matches(value, #"^[0-9a-f]{40}$"#)
    }

    private enum DownloadKind {
        case release
        case rawProvenance
    }

    private func validateReleasePage() throws {
        guard Self.isPlainHTTPS(releasePageURL),
              releasePageURL.host?.lowercased() == "github.com",
              releasePageURL.path == "/\(Self.sourceRepository)/releases/tag/\(tag)"
        else {
            throw ValidationError.insecureURL
        }
    }

    private func validateDownloads(_ record: FileRecord, kind: DownloadKind) throws {
        guard record.downloads.map(\.source) == Source.allCases else {
            throw ValidationError.invalidDownloadSources
        }
        for download in record.downloads {
            guard Self.isPlainHTTPS(download.url) else {
                throw ValidationError.insecureURL
            }

            let expectedHost: String
            let expectedPath: String
            switch (kind, download.source) {
            case (.release, .github):
                expectedHost = "github.com"
                expectedPath = "/\(Self.sourceRepository)/releases/download/\(tag)/\(record.file)"
            case (.release, .gitee):
                expectedHost = "gitee.com"
                expectedPath = "/\(Self.sourceRepository)/releases/download/\(tag)/\(record.file)"
            case (.rawProvenance, .github):
                expectedHost = "raw.githubusercontent.com"
                expectedPath = "/\(Self.sourceRepository)/\(Self.githubUpdateBranch)/updates/\(version)/\(record.file)"
            case (.rawProvenance, .gitee):
                expectedHost = "gitee.com"
                expectedPath = "/\(Self.sourceRepository)/raw/\(Self.giteeUpdateBranch)/updates/\(version)/\(record.file)"
            }
            guard download.url.host?.lowercased() == expectedHost,
                  download.url.path == expectedPath
            else {
                throw ValidationError.insecureURL
            }
        }
    }

    private static func isPlainHTTPS(_ url: URL) -> Bool {
        url.scheme == "https"
            && url.user == nil
            && url.password == nil
            && url.port == nil
            && url.query == nil
            && url.fragment == nil
    }

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }

    private static func validateExactShape(_ data: Data) throws {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ValidationError.malformedDocument
        }
        guard let root = object as? [String: Any] else {
            throw ValidationError.malformedDocument
        }
        let topLevelKeys: Set<String> = [
            "$schema", "schemaVersion", "policy", "releaseProfile", "releaseChannel",
            "version", "buildNumber", "tag", "commit", "bundleIdentifier",
            "pluginIdentifier", "architecture", "teamIdentifier", "minimumSystemVersion",
            "releasePageURL", "artifact", "provenance",
        ]
        guard Set(root.keys) == topLevelKeys else {
            throw ValidationError.unknownFields
        }
        for field in ["artifact", "provenance"] {
            guard let record = root[field] as? [String: Any],
                  Set(record.keys) == ["file", "sha256", "downloads"],
                  let downloads = record["downloads"] as? [[String: Any]],
                  downloads.count == 2,
                  downloads.allSatisfy({ Set($0.keys) == ["source", "url"] })
            else {
                throw ValidationError.unknownFields
            }
        }
    }
}

/// Loads the same update manifest from GitHub first and Gitee second.
public final class UpdateManifestLoader: @unchecked Sendable {
    public struct LoadedManifest: Sendable {
        public let manifest: UpdateManifest
    }

    public static let defaultURLs = [
        URL(string: "https://raw.githubusercontent.com/aulyc/aulycZip/release-channel/latest.json")!,
        URL(string: "https://gitee.com/aulyc/aulycZip/raw/main/latest.json")!,
    ]

    private let session: URLSession
    private let manifestURLs: [URL]
    private let userAgent: @Sendable () -> String

    public init(
        session: URLSession = .shared,
        manifestURLs: [URL] = UpdateManifestLoader.defaultURLs,
        userAgent: @escaping @Sendable () -> String
    ) {
        self.session = session
        self.manifestURLs = manifestURLs
        self.userAgent = userAgent
    }

    public func load(
        completion: @escaping @Sendable (Result<LoadedManifest, Error>) -> Void
    ) {
        load(at: 0, lastError: URLError(.cannotFindHost), completion: completion)
    }

    private func load(
        at index: Int,
        lastError: Error,
        completion: @escaping @Sendable (Result<LoadedManifest, Error>) -> Void
    ) {
        guard manifestURLs.indices.contains(index) else {
            completion(.failure(lastError))
            return
        }

        let url = manifestURLs[index]
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent(), forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            do {
                if let error { throw error }
                guard let http = response as? HTTPURLResponse,
                      http.statusCode == 200,
                      let data
                else {
                    throw URLError(.badServerResponse)
                }
                let manifest = try UpdateManifest.decodeValidated(from: data)
                completion(.success(LoadedManifest(manifest: manifest)))
            } catch {
                self.load(at: index + 1, lastError: error, completion: completion)
            }
        }.resume()
    }
}

public enum UpdateVersion {
    public static func isNewer(
        version: String,
        buildNumber: Int,
        thanVersion currentVersion: String,
        buildNumber currentBuildNumber: Int
    ) -> Bool {
        let candidate = components(version)
        let current = components(currentVersion)
        for index in 0..<max(candidate.count, current.count) {
            let left = index < candidate.count ? candidate[index] : 0
            let right = index < current.count ? current[index] : 0
            if left != right { return left > right }
        }
        return version == currentVersion && buildNumber > currentBuildNumber
    }

    private static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { part in
            Int(part.prefix(while: { $0.isNumber })) ?? 0
        }
    }
}
