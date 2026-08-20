import Foundation
import Testing
@testable import ZipCore

@Suite("ZIP archive integration")
struct ZipArchiveIntegrationTests {
    @Test("plain ZIP can be created, listed, and extracted")
    func plainRoundTrip() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("问候.txt")
            try Data("你好，aulycZip".utf8).write(to: source)

            try ZipArchive.create(at: fixture.archive, contentsOf: [source], encryption: .none)
            let entries = try ZipArchive.list(fixture.archive)

            #expect(entries.map(\.path) == ["问候.txt"])
            #expect(entries.first?.isEncrypted == false)

            try ZipArchive.extract(fixture.archive, to: fixture.output)
            let restored = try Data(contentsOf: fixture.output.appendingPathComponent("问候.txt"))
            #expect(restored == Data("你好，aulycZip".utf8))
        }
    }

    @Test("macOS metadata entries are hidden and not extracted")
    func ignoresMacOSMetadataEntries() throws {
        try withFixture { fixture in
            let document = fixture.source.appendingPathComponent("文档.pdf")
            let metadataDirectory = fixture.source.appendingPathComponent(
                "__MACOSX",
                isDirectory: true
            )
            let appleDouble = fixture.source.appendingPathComponent("._文档.pdf")
            let finderMetadata = fixture.source.appendingPathComponent(".DS_Store")
            try FileManager.default.createDirectory(
                at: metadataDirectory,
                withIntermediateDirectories: false
            )
            try Data("document".utf8).write(to: document)
            try Data("resource fork".utf8).write(
                to: metadataDirectory.appendingPathComponent("._文档.pdf")
            )
            try Data("apple double".utf8).write(to: appleDouble)
            try Data("finder metadata".utf8).write(to: finderMetadata)

            try ZipArchive.create(
                at: fixture.archive,
                contentsOf: [metadataDirectory, appleDouble, finderMetadata, document],
                encryption: .none
            )

            #expect(try ZipArchive.list(fixture.archive).map(\.path) == ["文档.pdf"])

            try ZipArchive.extract(fixture.archive, to: fixture.output)
            #expect(
                try Data(contentsOf: fixture.output.appendingPathComponent("文档.pdf"))
                    == Data("document".utf8)
            )
            #expect(
                try FileManager.default.contentsOfDirectory(atPath: fixture.output.path)
                    == ["文档.pdf"]
            )
        }
    }

    @Test("an existing directory can receive extracted files without an extra folder")
    func directExtractionIntoExistingDirectory() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("直接解压.txt")
            let original = Data("direct extraction".utf8)
            try original.write(to: source)
            try ZipArchive.create(at: fixture.archive, contentsOf: [source], encryption: .none)
            try FileManager.default.createDirectory(
                at: fixture.output,
                withIntermediateDirectories: false
            )

            try ZipArchive.extract(
                fixture.archive,
                to: fixture.output,
                destinationPolicy: .mergeIntoExistingDirectory
            )

            #expect(
                try Data(contentsOf: fixture.output.appendingPathComponent("直接解压.txt"))
                    == original
            )
        }
    }

    @Test("direct extraction refuses a conflicting item without changing it")
    func directExtractionRefusesConflicts() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("冲突.txt")
            let existing = Data("keep existing".utf8)
            try Data("new content".utf8).write(to: source)
            try ZipArchive.create(at: fixture.archive, contentsOf: [source], encryption: .none)
            try FileManager.default.createDirectory(
                at: fixture.output,
                withIntermediateDirectories: false
            )
            let conflict = fixture.output.appendingPathComponent("冲突.txt")
            try existing.write(to: conflict)

            #expect(throws: ZipError.destinationEntryAlreadyExists(conflict.path)) {
                try ZipArchive.extract(
                    fixture.archive,
                    to: fixture.output,
                    destinationPolicy: .mergeIntoExistingDirectory
                )
            }
            #expect(try Data(contentsOf: conflict) == existing)
            let leftovers = try FileManager.default.contentsOfDirectory(
                at: fixture.output,
                includingPropertiesForKeys: nil
            ).filter { $0.lastPathComponent.hasPrefix(".aulycZip-extract-") }
            #expect(leftovers.isEmpty)
        }
    }

    @Test("direct extraction preserves nested paths and multiple top-level items")
    func directExtractionPreservesArchiveStructure() throws {
        try withFixture { fixture in
            let folder = fixture.source.appendingPathComponent("资料", isDirectory: true)
            let nested = folder.appendingPathComponent("内部", isDirectory: true)
            let looseFile = fixture.source.appendingPathComponent("说明.txt")
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try Data("nested".utf8).write(to: nested.appendingPathComponent("内容.txt"))
            try Data("loose".utf8).write(to: looseFile)
            try ZipArchive.create(
                at: fixture.archive,
                contentsOf: [folder, looseFile],
                encryption: .none
            )
            try FileManager.default.createDirectory(
                at: fixture.output,
                withIntermediateDirectories: false
            )

            try ZipArchive.extract(
                fixture.archive,
                to: fixture.output,
                destinationPolicy: .mergeIntoExistingDirectory
            )

            #expect(
                try Data(contentsOf: fixture.output.appendingPathComponent("资料/内部/内容.txt"))
                    == Data("nested".utf8)
            )
            #expect(
                try Data(contentsOf: fixture.output.appendingPathComponent("说明.txt"))
                    == Data("loose".utf8)
            )
        }
    }

    @Test("wrong password writes nothing into an existing destination")
    func directExtractionRejectsWrongPasswordTransactionally() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("机密.txt")
            try Data("secret".utf8).write(to: source)
            try ZipArchive.create(
                at: fixture.archive,
                contentsOf: [source],
                encryption: .winZipAES256(password: "right-password")
            )
            try FileManager.default.createDirectory(
                at: fixture.output,
                withIntermediateDirectories: false
            )
            let marker = fixture.output.appendingPathComponent("保留.txt")
            try Data("keep".utf8).write(to: marker)

            #expect(throws: ZipError.wrongPassword) {
                try ZipArchive.extract(
                    fixture.archive,
                    to: fixture.output,
                    password: "wrong-password",
                    destinationPolicy: .mergeIntoExistingDirectory
                )
            }
            #expect(try Data(contentsOf: marker) == Data("keep".utf8))
            #expect(
                !FileManager.default.fileExists(
                    atPath: fixture.output.appendingPathComponent("机密.txt").path
                )
            )
            let leftovers = try FileManager.default.contentsOfDirectory(
                at: fixture.output,
                includingPropertiesForKeys: nil
            ).filter { $0.lastPathComponent.hasPrefix(".aulycZip-extract-") }
            #expect(leftovers.isEmpty)
        }
    }

    @Test("cancelled direct extraction leaves an existing destination unchanged")
    func directExtractionCancellationRollsBack() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("取消.txt")
            try Data("cancel".utf8).write(to: source)
            try ZipArchive.create(at: fixture.archive, contentsOf: [source], encryption: .none)
            try FileManager.default.createDirectory(
                at: fixture.output,
                withIntermediateDirectories: false
            )
            let marker = fixture.output.appendingPathComponent("保留.txt")
            try Data("keep".utf8).write(to: marker)
            let cancellation = ZipOperationCancellation()
            cancellation.cancel()

            #expect(throws: ZipError.cancelled) {
                try ZipArchive.extract(
                    fixture.archive,
                    to: fixture.output,
                    destinationPolicy: .mergeIntoExistingDirectory,
                    cancellation: cancellation
                )
            }
            #expect(try Data(contentsOf: marker) == Data("keep".utf8))
            #expect(
                !FileManager.default.fileExists(
                    atPath: fixture.output.appendingPathComponent("取消.txt").path
                )
            )
        }
    }

    @Test("direct extraction rejects a symbolic-link destination root")
    func directExtractionRejectsSymbolicLinkDestination() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("逃逸.txt")
            let outside = fixture.root.appendingPathComponent("outside", isDirectory: true)
            try Data("blocked".utf8).write(to: source)
            try ZipArchive.create(at: fixture.archive, contentsOf: [source], encryption: .none)
            try FileManager.default.createDirectory(
                at: outside,
                withIntermediateDirectories: false
            )
            try FileManager.default.createSymbolicLink(
                at: fixture.output,
                withDestinationURL: outside
            )

            #expect(throws: ZipError.unsafeEntryPath(fixture.output.path)) {
                try ZipArchive.extract(
                    fixture.archive,
                    to: fixture.output,
                    destinationPolicy: .mergeIntoExistingDirectory
                )
            }
            #expect(
                !FileManager.default.fileExists(
                    atPath: outside.appendingPathComponent("逃逸.txt").path
                )
            )
        }
    }

    @Test("direct extraction requires an existing directory destination")
    func directExtractionRejectsMissingDestination() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("内容.txt")
            try Data("content".utf8).write(to: source)
            try ZipArchive.create(at: fixture.archive, contentsOf: [source], encryption: .none)

            #expect(throws: ZipError.unsafeEntryPath(fixture.output.path)) {
                try ZipArchive.extract(
                    fixture.archive,
                    to: fixture.output,
                    destinationPolicy: .mergeIntoExistingDirectory
                )
            }
            #expect(!FileManager.default.fileExists(atPath: fixture.output.path))
        }
    }

    @Test("folder hierarchy round-trips")
    func folderRoundTrip() throws {
        try withFixture { fixture in
            let folder = fixture.source.appendingPathComponent("资料", isDirectory: true)
            let nested = folder.appendingPathComponent("内部", isDirectory: true)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try Data("secret".utf8).write(to: nested.appendingPathComponent("内容.txt"))

            try ZipArchive.create(at: fixture.archive, contentsOf: [folder], encryption: .none)
            let paths = try ZipArchive.list(fixture.archive).map(\.path)

            #expect(paths.contains("资料/"))
            #expect(paths.contains("资料/内部/"))
            #expect(paths.contains("资料/内部/内容.txt"))

            try ZipArchive.extract(fixture.archive, to: fixture.output)
            let restored = try Data(contentsOf: fixture.output.appendingPathComponent("资料/内部/内容.txt"))
            #expect(restored == Data("secret".utf8))
        }
    }

    @Test("WinZip AES-256 archive round-trips")
    func encryptedRoundTrip() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("机密.txt")
            let original = Data(String(repeating: "confidential-", count: 128).utf8)
            try original.write(to: source)

            try ZipArchive.create(
                at: fixture.archive,
                contentsOf: [source],
                encryption: .winZipAES256(password: "correct horse battery staple")
            )
            let entries = try ZipArchive.list(fixture.archive)
            #expect(entries.first?.isEncrypted == true)
            #expect(entries.first?.encryption == .winZipAES256)

            try ZipArchive.extract(
                fixture.archive,
                to: fixture.output,
                password: "correct horse battery staple"
            )
            #expect(try Data(contentsOf: fixture.output.appendingPathComponent("机密.txt")) == original)
        }
    }

    @Test("a pure-Chinese password encrypts and decrypts an AES-256 archive")
    func pureChinesePasswordRoundTrip() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("中文机密.txt")
            let original = Data("这是一份使用纯中文密码保护的内容。".utf8)
            let password = "中文密码安全测试"
            try original.write(to: source)

            try ZipArchive.create(
                at: fixture.archive,
                contentsOf: [source],
                encryption: .winZipAES256(password: password)
            )
            try ZipArchive.extract(
                fixture.archive,
                to: fixture.output,
                password: password
            )

            #expect(
                try Data(contentsOf: fixture.output.appendingPathComponent("中文机密.txt"))
                    == original
            )
        }
    }

    @Test("wrong password is rejected without writing plaintext")
    func wrongPassword() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("secret.txt")
            try Data("secret".utf8).write(to: source)
            try ZipArchive.create(
                at: fixture.archive,
                contentsOf: [source],
                encryption: .winZipAES256(password: "right-password")
            )

            #expect(throws: ZipError.wrongPassword) {
                try ZipArchive.extract(fixture.archive, to: fixture.output, password: "wrong-password")
            }
            #expect(!FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("secret.txt").path))
        }
    }

    @Test("tampered AES payload fails authentication")
    func tamperedPayload() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("secret.txt")
            try Data(String(repeating: "secret", count: 100).utf8).write(to: source)
            try ZipArchive.create(
                at: fixture.archive,
                contentsOf: [source],
                encryption: .winZipAES256(password: "right-password")
            )

            let record = try #require(try ZipArchiveReader(data: Data(contentsOf: fixture.archive)).records.first)
            var bytes = try Data(contentsOf: fixture.archive)
            let encryptedByte = Int(record.dataOffset) + 16 + 2
            bytes[encryptedByte] ^= 0x01
            try bytes.write(to: fixture.archive)

            #expect(throws: ZipError.authenticationFailed) {
                try ZipArchive.extract(fixture.archive, to: fixture.output, password: "right-password")
            }
            #expect(!FileManager.default.fileExists(atPath: fixture.output.path))
        }
    }

    @Test("archive output cannot overwrite an input file")
    func rejectsDestinationMatchingSource() throws {
        try withFixture { fixture in
            try Data("original input".utf8).write(to: fixture.archive)
            #expect(throws: ZipError.destinationMatchesSource) {
                try ZipArchive.create(
                    at: fixture.archive,
                    contentsOf: [fixture.archive],
                    encryption: .none
                )
            }
            #expect(try Data(contentsOf: fixture.archive) == Data("original input".utf8))
        }
    }

    @Test("archive creation refuses an existing destination by default")
    func creationRefusesExistingDestinationByDefault() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("new.txt")
            let existing = Data("existing archive must survive".utf8)
            try Data("new archive content".utf8).write(to: source)
            try existing.write(to: fixture.archive)

            #expect(throws: ZipError.destinationAlreadyExists(fixture.archive.path)) {
                try ZipArchive.create(
                    at: fixture.archive,
                    contentsOf: [source],
                    encryption: .none
                )
            }
            #expect(try Data(contentsOf: fixture.archive) == existing)
        }
    }

    @Test("a newly created archive follows the process default file permissions")
    func creationUsesDefaultFilePermissions() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("new.txt")
            let reference = fixture.root.appendingPathComponent("default-permissions-reference")
            try Data("new archive content".utf8).write(to: source)
            #expect(FileManager.default.createFile(atPath: reference.path, contents: Data()))
            let expectedPermissions = try posixPermissions(at: reference)

            try ZipArchive.create(
                at: fixture.archive,
                contentsOf: [source],
                encryption: .none
            )

            #expect(try posixPermissions(at: fixture.archive) == expectedPermissions)
        }
    }

    @Test("explicit replacement atomically replaces an existing archive")
    func creationReplacesExistingDestinationWhenAuthorized() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("new.txt")
            try Data("new archive content".utf8).write(to: source)
            #expect(FileManager.default.createFile(
                atPath: fixture.archive.path,
                contents: Data("old archive content".utf8)
            ))
            let expectedPermissions = try posixPermissions(at: fixture.archive)

            try ZipArchive.create(
                at: fixture.archive,
                contentsOf: [source],
                encryption: .none,
                destinationPolicy: .replaceExisting
            )

            #expect(try ZipArchive.list(fixture.archive).map(\.path) == ["new.txt"])
            #expect(try posixPermissions(at: fixture.archive) == expectedPermissions)
        }
    }

    @Test("cancelling an authorized replacement preserves the existing archive")
    func cancelledReplacementPreservesExistingDestination() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("new.txt")
            let existing = Data("existing archive must survive cancellation".utf8)
            try Data("new archive content".utf8).write(to: source)
            try existing.write(to: fixture.archive)
            let cancellation = ZipOperationCancellation()
            cancellation.cancel()

            #expect(throws: ZipError.cancelled) {
                try ZipArchive.create(
                    at: fixture.archive,
                    contentsOf: [source],
                    encryption: .none,
                    destinationPolicy: .replaceExisting,
                    cancellation: cancellation
                )
            }
            #expect(try Data(contentsOf: fixture.archive) == existing)
        }
    }

    @Test("authorized replacement never replaces a directory")
    func replacementRefusesDirectoryDestination() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("new.txt")
            try Data("new archive content".utf8).write(to: source)
            try FileManager.default.createDirectory(
                at: fixture.archive,
                withIntermediateDirectories: false
            )
            let marker = fixture.archive.appendingPathComponent("keep.txt")
            try Data("keep directory".utf8).write(to: marker)

            #expect(throws: ZipError.destinationAlreadyExists(fixture.archive.path)) {
                try ZipArchive.create(
                    at: fixture.archive,
                    contentsOf: [source],
                    encryption: .none,
                    destinationPolicy: .replaceExisting
                )
            }
            #expect(try Data(contentsOf: marker) == Data("keep directory".utf8))
        }
    }

    @Test("authorized replacement never follows a symbolic-link destination")
    func replacementRefusesSymbolicLinkDestination() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("new.txt")
            let outside = fixture.root.appendingPathComponent("outside.zip")
            let existing = Data("outside archive must survive".utf8)
            try Data("new archive content".utf8).write(to: source)
            try existing.write(to: outside)
            try FileManager.default.createSymbolicLink(
                at: fixture.archive,
                withDestinationURL: outside
            )

            #expect(throws: ZipError.destinationAlreadyExists(fixture.archive.path)) {
                try ZipArchive.create(
                    at: fixture.archive,
                    contentsOf: [source],
                    encryption: .none,
                    destinationPolicy: .replaceExisting
                )
            }
            let values = try fixture.archive.resourceValues(forKeys: [.isSymbolicLinkKey])
            #expect(values.isSymbolicLink == true)
            #expect(try Data(contentsOf: outside) == existing)
        }
    }

    @Test("a symbolic-link destination root is rejected")
    func rejectsSymbolicLinkDestinationRoot() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("safe.txt")
            try Data("safe".utf8).write(to: source)
            try ZipArchive.create(at: fixture.archive, contentsOf: [source], encryption: .none)

            let outside = fixture.root.appendingPathComponent("outside", isDirectory: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: fixture.output, withDestinationURL: outside)

            #expect(throws: ZipError.unsafeEntryPath(fixture.output.path)) {
                try ZipArchive.extract(fixture.archive, to: fixture.output)
            }
            #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("safe.txt").path))
        }
    }

    @Test("extraction keeps plaintext owner-only and does not restore execute bits")
    func extractionUsesOwnerOnlyPermissions() throws {
        try withFixture { fixture in
            let folder = fixture.source.appendingPathComponent("payload", isDirectory: true)
            let executable = folder.appendingPathComponent("run.sh")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: executable.path
            )
            try ZipArchive.create(at: fixture.archive, contentsOf: [folder], encryption: .none)

            try ZipArchive.extract(fixture.archive, to: fixture.output)

            let restoredFolder = fixture.output.appendingPathComponent("payload", isDirectory: true)
            let restoredFile = restoredFolder.appendingPathComponent("run.sh")
            #expect(try posixPermissions(at: fixture.output) == 0o700)
            #expect(try posixPermissions(at: restoredFolder) == 0o700)
            #expect(try posixPermissions(at: restoredFile) == 0o600)
        }
    }

    @Test("an existing symbolic-link directory inside the destination is rejected")
    func rejectsSymbolicLinkDirectory() throws {
        try withFixture { fixture in
            let payload = fixture.source.appendingPathComponent("payload", isDirectory: true)
            let linked = payload.appendingPathComponent("linked", isDirectory: true)
            try FileManager.default.createDirectory(at: linked, withIntermediateDirectories: true)
            try Data("do not escape".utf8).write(to: linked.appendingPathComponent("secret.txt"))
            try ZipArchive.create(at: fixture.archive, contentsOf: [payload], encryption: .none)

            let outside = fixture.root.appendingPathComponent("outside", isDirectory: true)
            let outputPayload = fixture.output.appendingPathComponent("payload", isDirectory: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outputPayload, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                at: outputPayload.appendingPathComponent("linked", isDirectory: true),
                withDestinationURL: outside
            )

            #expect(throws: ZipError.self) {
                try ZipArchive.extract(fixture.archive, to: fixture.output)
            }
            #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("secret.txt").path))
        }
    }

    @Test("duplicate entry paths are rejected")
    func rejectsDuplicateEntryPaths() throws {
        try withFixture { fixture in
            let first = fixture.source.appendingPathComponent("a.txt")
            let second = fixture.source.appendingPathComponent("b.txt")
            try Data("first".utf8).write(to: first)
            try Data("second".utf8).write(to: second)
            try ZipArchive.create(at: fixture.archive, contentsOf: [first, second], encryption: .none)

            var bytes = try Data(contentsOf: fixture.archive)
            replaceAll(Data("b.txt".utf8), with: Data("a.txt".utf8), in: &bytes)
            try bytes.write(to: fixture.archive)

            #expect(throws: ZipError.duplicateEntry("a.txt")) {
                _ = try ZipArchive.list(fixture.archive)
            }
        }
    }

    @Test("forced ZIP64 plain archive can be listed and extracted")
    func zip64PlainRoundTrip() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("zip64.txt")
            let original = Data(String(repeating: "ZIP64-stream-", count: 5_000).utf8)
            try original.write(to: source)

            try ZipArchiveWriter.create(
                at: fixture.archive,
                contentsOf: [source],
                encryption: .none,
                options: ZipArchiveWriterOptions(forceZIP64: true)
            )

            let bytes = try Data(contentsOf: fixture.archive)
            #expect(bytes.containsSignature(0x0606_4B50))
            #expect(bytes.containsSignature(0x0706_4B50))
            #expect(try ZipArchive.list(fixture.archive).first?.uncompressedSize == UInt64(original.count))

            try ZipArchive.extract(fixture.archive, to: fixture.output)
            #expect(try Data(contentsOf: fixture.output.appendingPathComponent("zip64.txt")) == original)
        }
    }

    @Test("forced ZIP64 WinZip AES archive follows the same authentication path")
    func zip64AESRoundTrip() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("zip64-secret.txt")
            let original = Data(String(repeating: "authenticated-", count: 8_000).utf8)
            try original.write(to: source)

            try ZipArchiveWriter.create(
                at: fixture.archive,
                contentsOf: [source],
                encryption: .winZipAES256(password: "zip64-password"),
                options: ZipArchiveWriterOptions(forceZIP64: true)
            )
            try ZipArchive.extract(
                fixture.archive,
                to: fixture.output,
                password: "zip64-password"
            )

            #expect(try Data(contentsOf: fixture.output.appendingPathComponent("zip64-secret.txt")) == original)
        }
    }

    @Test("ordinary small archives stay in classic ZIP format")
    func classicZIPRemainsClassic() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("classic.txt")
            try Data("classic".utf8).write(to: source)
            try ZipArchive.create(at: fixture.archive, contentsOf: [source], encryption: .none)

            let bytes = try Data(contentsOf: fixture.archive)
            #expect(!bytes.containsSignature(0x0606_4B50))
            #expect(!bytes.containsSignature(0x0706_4B50))
        }
    }

    @Test("ZIP64 locator declaring multiple disks is rejected")
    func rejectsMultiDiskZIP64() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("multi.txt")
            try Data("multi".utf8).write(to: source)
            try ZipArchiveWriter.create(
                at: fixture.archive,
                contentsOf: [source],
                encryption: .none,
                options: ZipArchiveWriterOptions(forceZIP64: true)
            )
            var bytes = try Data(contentsOf: fixture.archive)
            let locator = try #require(bytes.lastOffset(ofSignature: 0x0706_4B50))
            bytes.replaceLittleEndian(UInt32(2), at: locator + 16)
            try bytes.write(to: fixture.archive)

            #expect(throws: ZipError.unsupportedFeature("Multi-disk ZIP archives are not supported")) {
                _ = try ZipArchive.list(fixture.archive)
            }
        }
    }

    @Test("declared entry size limits actual streamed output")
    func declaredEntrySizeLimitsActualOutput() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("large.txt")
            try Data(repeating: 0x41, count: 64 * 1024).write(to: source)
            try ZipArchive.create(at: fixture.archive, contentsOf: [source], encryption: .none)
            var bytes = try Data(contentsOf: fixture.archive)
            let local = try #require(bytes.firstOffset(ofSignature: 0x0403_4B50))
            let central = try #require(bytes.firstOffset(ofSignature: 0x0201_4B50))
            bytes.replaceLittleEndian(UInt32(512), at: local + 22)
            bytes.replaceLittleEndian(UInt32(512), at: central + 24)
            try bytes.write(to: fixture.archive)

            #expect(throws: ZipError.outputLimitExceeded) {
                try ZipArchive.extract(fixture.archive, to: fixture.output)
            }
            #expect(!FileManager.default.fileExists(atPath: fixture.output.path))
        }
    }

    @Test("case-insensitive path collisions are rejected before staging")
    func rejectsCaseInsensitiveCollision() throws {
        try withFixture { fixture in
            let upper = fixture.source.appendingPathComponent("A.txt")
            let other = fixture.source.appendingPathComponent("B.txt")
            try Data("upper".utf8).write(to: upper)
            try Data("lower".utf8).write(to: other)
            try ZipArchive.create(at: fixture.archive, contentsOf: [upper, other], encryption: .none)
            var bytes = try Data(contentsOf: fixture.archive)
            replaceAll(Data("B.txt".utf8), with: Data("a.txt".utf8), in: &bytes)
            try bytes.write(to: fixture.archive)

            #expect(throws: ZipError.duplicateEntry("a.txt")) {
                try ZipArchive.extract(fixture.archive, to: fixture.output)
            }
            #expect(!FileManager.default.fileExists(atPath: fixture.output.path))
        }
    }

    @Test("ZIP64 sentinel fields require a valid locator")
    func missingZIP64LocatorIsRejected() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("locator.txt")
            try Data("locator".utf8).write(to: source)
            try ZipArchiveWriter.create(
                at: fixture.archive,
                contentsOf: [source],
                encryption: .none,
                options: ZipArchiveWriterOptions(forceZIP64: true)
            )
            var bytes = try Data(contentsOf: fixture.archive)
            let locator = try #require(bytes.lastOffset(ofSignature: 0x0706_4B50))
            bytes.replaceLittleEndian(UInt32(0), at: locator)
            try bytes.write(to: fixture.archive)

            #expect(throws: ZipError.invalidArchive("ZIP64 locator was not found")) {
                _ = try ZipArchive.list(fixture.archive)
            }
        }
    }

    @Test("ZIP64 local size sentinels require a matching extra field")
    func missingLocalZIP64ExtraIsRejected() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("extra.txt")
            try Data("extra".utf8).write(to: source)
            try ZipArchiveWriter.create(
                at: fixture.archive,
                contentsOf: [source],
                encryption: .none,
                options: ZipArchiveWriterOptions(forceZIP64: true)
            )
            var bytes = try Data(contentsOf: fixture.archive)
            let local = try #require(bytes.firstOffset(ofSignature: 0x0403_4B50))
            var lengths = ByteCursor(data: bytes, offset: local + 26)
            let nameLength = try lengths.readUInt16()
            let extraOffset = local + 30 + Int(nameLength)
            bytes.replaceLittleEndian(UInt16(0x0002), at: extraOffset)
            try bytes.write(to: fixture.archive)

            #expect(throws: ZipError.invalidArchive("ZIP64 extra field was not found")) {
                _ = try ZipArchive.list(fixture.archive)
            }
        }
    }

    @Test("late CRC failure removes staging output and leaves no final directory")
    func lateFailureIsTransactional() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("crc.txt")
            try Data(String(repeating: "crc-payload", count: 1_000).utf8).write(to: source)
            try ZipArchive.create(at: fixture.archive, contentsOf: [source], encryption: .none)

            var bytes = try Data(contentsOf: fixture.archive)
            let local = try #require(bytes.firstOffset(ofSignature: 0x0403_4B50))
            let central = try #require(bytes.firstOffset(ofSignature: 0x0201_4B50))
            bytes.replaceLittleEndian(UInt32(0xDEAD_BEEF), at: local + 14)
            bytes.replaceLittleEndian(UInt32(0xDEAD_BEEF), at: central + 16)
            try bytes.write(to: fixture.archive)

            #expect(throws: ZipError.invalidArchive("CRC-32 validation failed")) {
                try ZipArchive.extract(fixture.archive, to: fixture.output)
            }
            #expect(!FileManager.default.fileExists(atPath: fixture.output.path))
            let leftovers = try FileManager.default.contentsOfDirectory(
                at: fixture.root,
                includingPropertiesForKeys: nil
            ).filter { $0.lastPathComponent.hasPrefix(".aulycZip-extract-") }
            #expect(leftovers.isEmpty)
        }
    }

    @Test("existing final destination is never overwritten")
    func existingDestinationIsRejected() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("safe.txt")
            try Data("safe".utf8).write(to: source)
            try ZipArchive.create(at: fixture.archive, contentsOf: [source], encryption: .none)
            try FileManager.default.createDirectory(at: fixture.output, withIntermediateDirectories: true)
            let marker = fixture.output.appendingPathComponent("keep.txt")
            try Data("keep".utf8).write(to: marker)

            #expect(throws: ZipError.destinationAlreadyExists(fixture.output.path)) {
                try ZipArchive.extract(fixture.archive, to: fixture.output)
            }
            #expect(try Data(contentsOf: marker) == Data("keep".utf8))
        }
    }

    @Test("path and free-space limits are enforced before staging")
    func pathAndDiskLimits() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("bounded-name.txt")
            try Data("bounded".utf8).write(to: source)
            try ZipArchive.create(at: fixture.archive, contentsOf: [source], encryption: .none)

            #expect(throws: ZipError.unsafeEntryPath("bounded-name.txt")) {
                try ZipArchive.extract(
                    fixture.archive,
                    to: fixture.output,
                    limits: ZipExtractionLimits(
                        maximumEntryCount: 100,
                        maximumEntryUncompressedSize: 1_024,
                        maximumTotalUncompressedSize: 1_024,
                        maximumPathUTF8ByteCount: 8,
                        minimumFreeSpaceReserve: 0
                    )
                )
            }
            #expect(!FileManager.default.fileExists(atPath: fixture.output.path))
        }
    }

    @Test("WinZip AES-128, AES-192, and AES-256 AE-1/AE-2 fixtures are readable")
    func readsAllSupportedAESVariants() throws {
        for strength in [WinZipAESStrength.aes128, .aes192, .aes256] {
            for vendorVersion: UInt16 in [1, 2] {
                try withFixture { fixture in
                    let path = "aes-\(strength.rawValue)-ae-\(vendorVersion).txt"
                    let original = Data(String(repeating: "variant-", count: 1_000).utf8)
                    try makeAESFixture(
                        path: path,
                        contents: original,
                        password: "variant-password",
                        strength: strength,
                        vendorVersion: vendorVersion
                    ).write(to: fixture.archive)

                    try ZipArchive.extract(
                        fixture.archive,
                        to: fixture.output,
                        password: "variant-password"
                    )
                    #expect(try Data(contentsOf: fixture.output.appendingPathComponent(path)) == original)
                }
            }
        }
    }

    @Test("classic multi-disk and ZipCrypto archives are rejected explicitly")
    func rejectsUnsupportedClassicFeatures() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("unsupported.txt")
            try Data("unsupported".utf8).write(to: source)
            try ZipArchive.create(at: fixture.archive, contentsOf: [source], encryption: .none)

            var multiDisk = try Data(contentsOf: fixture.archive)
            let eocd = try #require(multiDisk.lastOffset(ofSignature: 0x0605_4B50))
            multiDisk.replaceLittleEndian(UInt16(1), at: eocd + 4)
            try multiDisk.write(to: fixture.archive)
            #expect(throws: ZipError.unsupportedFeature("Multi-disk ZIP archives are not supported")) {
                _ = try ZipArchive.list(fixture.archive)
            }

            try ZipArchiveWriter.create(
                at: fixture.root.appendingPathComponent("zipcrypto.zip"),
                contentsOf: [source],
                encryption: .none
            )
            let zipCryptoURL = fixture.root.appendingPathComponent("zipcrypto.zip")
            var zipCrypto = try Data(contentsOf: zipCryptoURL)
            let local = try #require(zipCrypto.firstOffset(ofSignature: 0x0403_4B50))
            let central = try #require(zipCrypto.firstOffset(ofSignature: 0x0201_4B50))
            zipCrypto.replaceLittleEndian(UInt16((1 << 11) | 1), at: local + 6)
            zipCrypto.replaceLittleEndian(UInt16((1 << 11) | 1), at: central + 8)
            try zipCrypto.write(to: zipCryptoURL)
            #expect(throws: ZipError.unsupportedFeature("Traditional ZipCrypto encryption is not supported")) {
                _ = try ZipArchive.list(zipCryptoURL)
            }
        }
    }

    @Test("ZIP64 entry count is limited before central-directory allocation")
    func zip64EntryCountLimit() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("count.txt")
            try Data("count".utf8).write(to: source)
            try ZipArchiveWriter.create(
                at: fixture.archive,
                contentsOf: [source],
                encryption: .none,
                options: ZipArchiveWriterOptions(forceZIP64: true)
            )
            var bytes = try Data(contentsOf: fixture.archive)
            let zip64End = try #require(bytes.lastOffset(ofSignature: 0x0606_4B50))
            bytes.replaceLittleEndian(UInt64(100_001), at: zip64End + 24)
            bytes.replaceLittleEndian(UInt64(100_001), at: zip64End + 32)
            try bytes.write(to: fixture.archive)

            #expect(throws: ZipError.tooManyEntries) {
                _ = try ZipArchive.list(fixture.archive)
            }
        }
    }

    @Test("third-party data descriptors are accepted using central-directory sizes")
    func readsDataDescriptorArchive() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("descriptor.txt")
            let original = Data(String(repeating: "descriptor-", count: 500).utf8)
            try original.write(to: source)
            try ZipArchive.create(at: fixture.archive, contentsOf: [source], encryption: .none)

            var bytes = try Data(contentsOf: fixture.archive)
            let local = try #require(bytes.firstOffset(ofSignature: 0x0403_4B50))
            let central = try #require(bytes.firstOffset(ofSignature: 0x0201_4B50))
            let eocd = try #require(bytes.lastOffset(ofSignature: 0x0605_4B50))
            var values = ByteCursor(data: bytes, offset: local + 14)
            let crc = try values.readUInt32()
            let compressedSize = try values.readUInt32()
            let uncompressedSize = try values.readUInt32()
            bytes.replaceLittleEndian(UInt16((1 << 11) | (1 << 3)), at: local + 6)
            bytes.replaceLittleEndian(UInt16((1 << 11) | (1 << 3)), at: central + 8)
            bytes.replaceLittleEndian(UInt32(0), at: local + 14)
            bytes.replaceLittleEndian(UInt32(0), at: local + 18)
            bytes.replaceLittleEndian(UInt32(0), at: local + 22)
            var descriptor = Data()
            descriptor.appendLittleEndian(UInt32(0x0807_4B50))
            descriptor.appendLittleEndian(crc)
            descriptor.appendLittleEndian(compressedSize)
            descriptor.appendLittleEndian(uncompressedSize)
            bytes.insert(contentsOf: descriptor, at: central)
            bytes.replaceLittleEndian(UInt32(central + descriptor.count), at: eocd + descriptor.count + 16)
            try bytes.write(to: fixture.archive)

            try ZipArchive.extract(fixture.archive, to: fixture.output)
            #expect(try Data(contentsOf: fixture.output.appendingPathComponent("descriptor.txt")) == original)
        }
    }

    @Test("cancellation rolls back creation and extraction transactions")
    func cancellationRollsBack() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("cancelled.txt")
            try Data(repeating: 0x43, count: 1024).write(to: source)
            let creationCancellation = ZipOperationCancellation()
            creationCancellation.cancel()
            #expect(throws: ZipError.cancelled) {
                try ZipArchive.create(
                    at: fixture.archive,
                    contentsOf: [source],
                    encryption: .none,
                    cancellation: creationCancellation
                )
            }
            #expect(!FileManager.default.fileExists(atPath: fixture.archive.path))

            try ZipArchive.create(at: fixture.archive, contentsOf: [source], encryption: .none)
            let extractionCancellation = ZipOperationCancellation()
            extractionCancellation.cancel()
            #expect(throws: ZipError.cancelled) {
                try ZipArchive.extract(
                    fixture.archive,
                    to: fixture.output,
                    cancellation: extractionCancellation
                )
            }
            #expect(!FileManager.default.fileExists(atPath: fixture.output.path))
        }
    }

    @Test("symbolic-link entries are rejected instead of materialized")
    func rejectsSymbolicLinkEntry() throws {
        try withFixture { fixture in
            let source = fixture.source.appendingPathComponent("link.txt")
            try Data("../outside".utf8).write(to: source)
            try ZipArchive.create(at: fixture.archive, contentsOf: [source], encryption: .none)
            var bytes = try Data(contentsOf: fixture.archive)
            let central = try #require(bytes.firstOffset(ofSignature: 0x0201_4B50))
            bytes.replaceLittleEndian(UInt32(0o120777 << 16), at: central + 38)
            try bytes.write(to: fixture.archive)

            #expect(throws: ZipError.unsupportedFeature("Symbolic links are not extracted")) {
                _ = try ZipArchive.list(fixture.archive)
            }
        }
    }
}

private struct Fixture {
    let root: URL
    let source: URL
    let output: URL
    let archive: URL
}

private func withFixture(_ body: (Fixture) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aulycZip-tests-\(UUID().uuidString)", isDirectory: true)
    let source = root.appendingPathComponent("source", isDirectory: true)
    let output = root.appendingPathComponent("output", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(Fixture(
        root: root,
        source: source,
        output: output,
        archive: root.appendingPathComponent("archive.zip")
    ))
}

private func replaceAll(_ old: Data, with replacement: Data, in data: inout Data) {
    precondition(old.count == replacement.count)
    guard old.count <= data.count else { return }
    for offset in stride(from: data.count - old.count, through: 0, by: -1) {
        if data[offset..<(offset + old.count)] == old[...] {
            data.replaceSubrange(offset..<(offset + old.count), with: replacement)
        }
    }
}

private func posixPermissions(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard let permissions = attributes[.posixPermissions] as? NSNumber else {
        throw ZipError.invalidArchive("POSIX permissions are unavailable for test fixture")
    }
    return permissions.intValue & 0o7777
}

private extension Data {
    func containsSignature(_ signature: UInt32) -> Bool {
        firstOffset(ofSignature: signature) != nil
    }

    func firstOffset(ofSignature signature: UInt32) -> Int? {
        var encoded = Data()
        encoded.appendLittleEndian(signature)
        return range(of: encoded)?.lowerBound
    }

    func lastOffset(ofSignature signature: UInt32) -> Int? {
        var encoded = Data()
        encoded.appendLittleEndian(signature)
        return range(of: encoded, options: .backwards)?.lowerBound
    }

    mutating func replaceLittleEndian<T: FixedWidthInteger>(_ value: T, at offset: Int) {
        var encoded = Data()
        encoded.appendLittleEndian(value)
        replaceSubrange(offset..<(offset + encoded.count), with: encoded)
    }
}

private func makeAESFixture(
    path: String,
    contents: Data,
    password: String,
    strength: WinZipAESStrength,
    vendorVersion: UInt16
) throws -> Data {
    let compressed = try RawDeflate.compress(contents)
    let crc = CRC32.checksum(contents)
    let salt = Data((0..<strength.saltByteCount).map { UInt8($0 + 1) })
    let material = try WinZipAESKeyMaterial.derive(
        password: password,
        salt: salt,
        strength: strength
    )
    var encryptor = try WinZipAESCTR(key: material.encryptionKey)
    let encrypted = try encryptor.update(compressed)
    let authentication = Data(
        HMACSHA1.authenticationCode(for: encrypted, key: material.authenticationKey).prefix(10)
    )
    let payload = salt + material.passwordVerification + encrypted + authentication
    let pathData = Data(path.utf8)
    var extra = Data()
    extra.appendLittleEndian(UInt16(0x9901))
    extra.appendLittleEndian(UInt16(7))
    extra.appendLittleEndian(vendorVersion)
    extra.append(contentsOf: [0x41, 0x45])
    extra.append(strength.rawValue)
    extra.appendLittleEndian(UInt16(8))
    let headerCRC = vendorVersion == 1 ? crc : 0
    let flags: UInt16 = (1 << 11) | 1

    var archive = Data()
    archive.appendLittleEndian(UInt32(0x0403_4B50))
    archive.appendLittleEndian(UInt16(51))
    archive.appendLittleEndian(flags)
    archive.appendLittleEndian(UInt16(99))
    archive.appendLittleEndian(UInt16(0))
    archive.appendLittleEndian(UInt16(0))
    archive.appendLittleEndian(headerCRC)
    archive.appendLittleEndian(UInt32(payload.count))
    archive.appendLittleEndian(UInt32(contents.count))
    archive.appendLittleEndian(UInt16(pathData.count))
    archive.appendLittleEndian(UInt16(extra.count))
    archive.append(pathData)
    archive.append(extra)
    archive.append(payload)

    let centralOffset = UInt32(archive.count)
    archive.appendLittleEndian(UInt32(0x0201_4B50))
    archive.appendLittleEndian(UInt16(0x033F))
    archive.appendLittleEndian(UInt16(51))
    archive.appendLittleEndian(flags)
    archive.appendLittleEndian(UInt16(99))
    archive.appendLittleEndian(UInt16(0))
    archive.appendLittleEndian(UInt16(0))
    archive.appendLittleEndian(headerCRC)
    archive.appendLittleEndian(UInt32(payload.count))
    archive.appendLittleEndian(UInt32(contents.count))
    archive.appendLittleEndian(UInt16(pathData.count))
    archive.appendLittleEndian(UInt16(extra.count))
    archive.appendLittleEndian(UInt16(0))
    archive.appendLittleEndian(UInt16(0))
    archive.appendLittleEndian(UInt16(0))
    archive.appendLittleEndian(UInt32(0o100644 << 16))
    archive.appendLittleEndian(UInt32(0))
    archive.append(pathData)
    archive.append(extra)
    let centralSize = UInt32(archive.count) - centralOffset
    archive.appendLittleEndian(UInt32(0x0605_4B50))
    archive.appendLittleEndian(UInt16(0))
    archive.appendLittleEndian(UInt16(0))
    archive.appendLittleEndian(UInt16(1))
    archive.appendLittleEndian(UInt16(1))
    archive.appendLittleEndian(centralSize)
    archive.appendLittleEndian(centralOffset)
    archive.appendLittleEndian(UInt16(0))
    return archive
}
