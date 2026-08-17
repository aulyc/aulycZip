import AppKit
import Foundation

@MainActor
public final class FinderServiceProvider: NSObject {
    private let onSelection: @MainActor ([URL]) -> Void

    public init(onSelection: @escaping @MainActor ([URL]) -> Void) {
        self.onSelection = onSelection
        super.init()
    }

    @objc(createEncryptedZip:userData:error:)
    public func createEncryptedZip(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        errorPointer.pointee = nil
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options) ?? []
        let urls = objects.compactMap { object -> URL? in
            guard let nsURL = object as? NSURL else { return nil }
            let url = nsURL as URL
            return url.isFileURL ? url : nil
        }
        guard !urls.isEmpty else {
            errorPointer.pointee = "Finder 没有提供可压缩的文件或文件夹" as NSString
            return
        }
        onSelection(urls)
    }
}
