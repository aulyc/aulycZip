import AppKit
import Foundation

@MainActor
public final class FinderServiceProvider: NSObject {
    private let onCreateSelection: @MainActor ([URL]) -> Void
    private let onExtractSelection: @MainActor (URL) -> Void

    public init(
        onCreateSelection: @escaping @MainActor ([URL]) -> Void,
        onExtractSelection: @escaping @MainActor (URL) -> Void
    ) {
        self.onCreateSelection = onCreateSelection
        self.onExtractSelection = onExtractSelection
        super.init()
    }

    @objc(createEncryptedZip:userData:error:)
    public func createEncryptedZip(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        errorPointer.pointee = nil
        let urls = fileURLs(from: pasteboard)
        guard !urls.isEmpty else {
            errorPointer.pointee = "Finder 没有提供可压缩的文件或文件夹" as NSString
            return
        }
        onCreateSelection(urls)
    }

    @objc(extractZip:userData:error:)
    public func extractZip(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        errorPointer.pointee = nil
        let urls = fileURLs(from: pasteboard)
        guard urls.count == 1 else {
            errorPointer.pointee = "请在 Finder 中只选择一个 ZIP 文件进行解压" as NSString
            return
        }
        let archive = urls[0]
        guard archive.pathExtension.caseInsensitiveCompare("zip") == .orderedSame else {
            errorPointer.pointee = "Finder 没有提供可解压的 ZIP 文件" as NSString
            return
        }
        onExtractSelection(archive)
    }

    private func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options) ?? []
        return objects.compactMap { object -> URL? in
            guard let nsURL = object as? NSURL else { return nil }
            let url = nsURL as URL
            return url.isFileURL ? url : nil
        }
    }
}
