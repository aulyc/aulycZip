import Foundation
import Testing
import ZipCore
@testable import aulycZipAppSupport

@Suite("Encrypted archive creator")
struct EncryptedArchiveCreatorTests {
    @Test("the shared creation path creates an AES-256 archive at its reserved destination")
    func createsEncryptedArchive() throws {
        try withCreatorFixture { fixture in
            let source = fixture.root.appendingPathComponent("secret.txt")
            try Data("secret".utf8).write(to: source)
            let request = try EncryptedArchiveRequest(sourceURLs: [source])

            let created = try EncryptedArchiveCreator.create(
                request: request,
                password: "test-password"
            )

            #expect(created == request.destinationURL)
            #expect(try ZipArchive.list(created).first?.encryption == .winZipAES256)
        }
    }

    @Test("a destination created after naming is never overwritten")
    func refusesLateDestinationCollision() throws {
        try withCreatorFixture { fixture in
            let source = fixture.root.appendingPathComponent("secret.txt")
            try Data("secret".utf8).write(to: source)
            let request = try EncryptedArchiveRequest(sourceURLs: [source])
            let existing = Data("existing archive must survive".utf8)
            try existing.write(to: request.destinationURL)

            #expect(throws: EncryptedArchiveCreationError.destinationExists) {
                _ = try EncryptedArchiveCreator.create(
                    request: request,
                    password: "test-password"
                )
            }
            #expect(try Data(contentsOf: request.destinationURL) == existing)
            let remainingNames = try FileManager.default.contentsOfDirectory(atPath: fixture.root.path)
            #expect(!remainingNames.contains(where: { $0.hasPrefix(".aulycZip-") }))
        }
    }
}

private struct CreatorFixture {
    let root: URL
}

private func withCreatorFixture(_ body: (CreatorFixture) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aulycZip-creator-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(CreatorFixture(root: root))
}
