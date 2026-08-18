import Foundation
import Testing
@testable import aulycZipAppSupport

@Suite("Online update contract")
struct UpdateContractTests {
    @Test("Schema v2 manifest binds the exact product and mirror order")
    func validManifest() throws {
        let manifest = try UpdateManifest.decodeValidated(from: manifestData())

        #expect(manifest.version == "1.0.0")
        #expect(manifest.buildNumber == 2)
        #expect(manifest.bundleIdentifier == "com.aulyc.aulyczip")
        #expect(manifest.artifact.downloads.map(\.source) == [.github, .gitee])
        #expect(manifest.provenance.downloads.map(\.source) == [.github, .gitee])
        #expect(UpdateManifestLoader.defaultURLs.map(\.host) == [
            "raw.githubusercontent.com",
            "gitee.com",
        ])
    }

    @Test("Legacy, extended, and reordered manifests fail closed")
    func rejectsContractDrift() throws {
        var legacy = manifestObject()
        legacy["$schema"] = "urn:codex-engineering-standards:dual-mirror-latest:1"
        legacy["schemaVersion"] = 1
        try expectManifestFailure(legacy, .unsupportedSchema)

        var extended = manifestObject()
        extended["unexpected"] = "value"
        try expectManifestFailure(extended, .unknownFields)

        var reordered = manifestObject()
        var artifact = try #require(reordered["artifact"] as? [String: Any])
        artifact["downloads"] = Array(
            try #require(artifact["downloads"] as? [[String: Any]]).reversed()
        )
        reordered["artifact"] = artifact
        try expectManifestFailure(reordered, .invalidDownloadSources)
    }

    @Test("Manifest rejects alternate repositories and credential-bearing URLs")
    func rejectsUntrustedURLs() throws {
        var wrongRepository = manifestObject()
        var artifact = try #require(wrongRepository["artifact"] as? [String: Any])
        var downloads = try #require(artifact["downloads"] as? [[String: Any]])
        downloads[0]["url"] = "https://github.com/aulyc/other/releases/download/1.0.0/file.dmg"
        artifact["downloads"] = downloads
        wrongRepository["artifact"] = artifact
        try expectManifestFailure(wrongRepository, .insecureURL)

        var credentialURL = manifestObject()
        credentialURL["releasePageURL"] = "https://user@example.com/aulyc/aulycZip/releases/tag/1.0.0"
        try expectManifestFailure(credentialURL, .insecureURL)
    }

    @Test("Version comparison uses SemVer before build number")
    func versionComparison() {
        #expect(UpdateVersion.isNewer(
            version: "1.1.0",
            buildNumber: 1,
            thanVersion: "1.0.9",
            buildNumber: 99
        ))
        #expect(UpdateVersion.isNewer(
            version: "1.0.0",
            buildNumber: 3,
            thanVersion: "1.0.0",
            buildNumber: 2
        ))
        #expect(!UpdateVersion.isNewer(
            version: "1.0.0",
            buildNumber: 2,
            thanVersion: "1.0.0",
            buildNumber: 2
        ))
    }

    @Test("SHA-256 verification uses the downloaded bytes")
    func sha256() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("aulycZip-update-hash-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("abc".utf8).write(to: file)

        #expect(try UpdateInstaller.sha256(of: file)
            == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test("Provenance must match the immutable manifest identity")
    func provenanceValidation() throws {
        let manifest = try UpdateManifest.decodeValidated(from: manifestData())
        try UpdateInstaller.verifyProvenanceData(
            try jsonData(provenanceObject()),
            manifest: manifest
        )

        var tampered = provenanceObject()
        tampered["sourceRemoteTagCommit"] = String(repeating: "b", count: 40)
        do {
            try UpdateInstaller.verifyProvenanceData(
                try jsonData(tampered),
                manifest: manifest
            )
            Issue.record("Tampered provenance was accepted")
        } catch let error as UpdateInstaller.InstallError {
            #expect(error == .invalidProvenance)
        }
    }

    @Test("Automatic replacement is restricted to the installed app path")
    func installLocation() throws {
        do {
            try UpdateInstaller.validateCurrentInstallLocation(
                bundleURL: URL(fileURLWithPath: "/tmp/aulycZip.app", isDirectory: true)
            )
            Issue.record("Non-installed app path was accepted")
        } catch let error as UpdateInstaller.InstallError {
            #expect(error == .unsupportedInstallLocation)
        }
    }

    @Test("Replacement helper validates fixed destination and recoverable backup")
    func replacementHelper() throws {
        let source = URL(
            fileURLWithPath: "/tmp/aulycZip-update-test/replacement/aulycZip.app",
            isDirectory: true
        )
        let destination = URL(
            fileURLWithPath: "/Applications/aulycZip.app",
            isDirectory: true
        )
        let backup = URL(
            fileURLWithPath: "/Applications/.aulycZip-update-backup-42.app",
            isDirectory: true
        )
        let script = try UpdateInstaller.replacementScript(
            sourceApp: source,
            destinationApp: destination,
            backupApp: backup,
            currentPID: 42,
            expectedExecutableSHA256: String(repeating: "3", count: 64),
            expectedInfoPlistSHA256: String(repeating: "4", count: 64),
            expectedTeamIdentifier: "M9M7M2ARFD"
        )

        #expect(script.contains("[ \"$destination_app\" = \"/Applications/aulycZip.app\" ]"))
        #expect(script.contains("/bin/mv \"$destination_app\" \"$backup_app\""))
        #expect(script.contains("/bin/mv \"$backup_app\" \"$destination_app\""))
        #expect(script.contains("/usr/bin/shasum -a 256"))
        #expect(script.contains("/usr/bin/codesign --verify --deep --strict"))
        #expect(script.contains("TeamIdentifier=$expected_team_id"))
        #expect(script.contains("/usr/sbin/spctl -a -t exec"))
    }

    private func expectManifestFailure(
        _ object: [String: Any],
        _ expected: UpdateManifest.ValidationError
    ) throws {
        do {
            _ = try UpdateManifest.decodeValidated(from: jsonData(object))
            Issue.record("Invalid manifest was accepted")
        } catch let error as UpdateManifest.ValidationError {
            #expect(error == expected)
        }
    }

    private func manifestData() throws -> Data {
        try jsonData(manifestObject())
    }

    private func manifestObject() -> [String: Any] {
        let version = "1.0.0"
        let build = 2
        let commit = String(repeating: "a", count: 40)
        let stem = "aulycZip-\(version)-build.\(build)-formal-macos-arm64"
        let artifact = "\(stem).dmg"
        let provenance = "\(stem).release-provenance.json"
        return [
            "$schema": "urn:codex-engineering-standards:dual-mirror-latest:2",
            "schemaVersion": 2,
            "policy": "aulyc-dual-mirror-v1",
            "releaseProfile": "macos-arm64-app",
            "releaseChannel": "formal",
            "version": version,
            "buildNumber": build,
            "tag": version,
            "commit": commit,
            "bundleIdentifier": "com.aulyc.aulyczip",
            "pluginIdentifier": NSNull(),
            "architecture": "arm64",
            "teamIdentifier": "M9M7M2ARFD",
            "minimumSystemVersion": "14.0",
            "releasePageURL": "https://github.com/aulyc/aulycZip/releases/tag/\(version)",
            "artifact": [
                "file": artifact,
                "sha256": String(repeating: "1", count: 64),
                "downloads": [
                    [
                        "source": "github",
                        "url": "https://github.com/aulyc/aulycZip/releases/download/\(version)/\(artifact)",
                    ],
                    [
                        "source": "gitee",
                        "url": "https://gitee.com/aulyc/aulycZip/releases/download/\(version)/\(artifact)",
                    ],
                ],
            ],
            "provenance": [
                "file": provenance,
                "sha256": String(repeating: "2", count: 64),
                "downloads": [
                    [
                        "source": "github",
                        "url": "https://raw.githubusercontent.com/aulyc/aulycZip/release-channel/updates/\(version)/\(provenance)",
                    ],
                    [
                        "source": "gitee",
                        "url": "https://gitee.com/aulyc/aulycZip/raw/main/updates/\(version)/\(provenance)",
                    ],
                ],
            ],
        ]
    }

    private func provenanceObject() -> [String: Any] {
        let commit = String(repeating: "a", count: 40)
        let artifact = "aulycZip-1.0.0-build.2-formal-macos-arm64.dmg"
        return [
            "$schema": "urn:aulyc:release-provenance:1",
            "project": "aulycZip",
            "releaseProfile": "macos-arm64-app",
            "releaseChannel": "formal",
            "version": "1.0.0",
            "buildNumber": 2,
            "tag": "1.0.0",
            "commit": commit,
            "dirty": false,
            "builtAt": "2026-08-18T00:00:00Z",
            "artifacts": [[
                "file": artifact,
                "sha256": String(repeating: "1", count: 64),
            ]],
            "architecture": "arm64",
            "bundleIdentifier": "com.aulyc.aulyczip",
            "bundleName": "aulycZip",
            "executableName": "aulycZip",
            "minimumSystemVersion": "14.0",
            "signatureType": "developer-id",
            "teamIdentifier": "M9M7M2ARFD",
            "hardenedRuntime": true,
            "entitlements": [String: Any](),
            "notarized": true,
            "notarizationSubmissionId": "00000000-0000-0000-0000-000000000000",
            "appExecutableSha256": String(repeating: "3", count: 64),
            "infoPlistSha256": String(repeating: "4", count: 64),
            "sourceRepository": "aulyc/aulycZip",
            "sourceBranch": "main",
            "sourceRemoteCommit": commit,
            "sourceRemoteTagCommit": commit,
            "sourceRemoteVerifiedAt": "2026-08-18T00:05:00Z",
        ]
    }

    private func jsonData(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
