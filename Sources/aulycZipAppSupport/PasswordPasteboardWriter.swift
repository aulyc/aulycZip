import AppKit
import Foundation

public enum PasswordPasteboardWriter {
    public static let concealedType = NSPasteboard.PasteboardType(
        "org.nspasteboard.ConcealedType"
    )
    public static let transientType = NSPasteboard.PasteboardType(
        "org.nspasteboard.TransientType"
    )

    @discardableResult
    public static func write(
        _ password: String,
        to pasteboard: NSPasteboard = .general
    ) -> Bool {
        pasteboard.prepareForNewContents(with: .currentHostOnly)
        let item = NSPasteboardItem()
        item.setString(password, forType: .string)
        item.setData(Data(), forType: concealedType)
        item.setData(Data(), forType: transientType)
        return pasteboard.writeObjects([item])
    }
}
