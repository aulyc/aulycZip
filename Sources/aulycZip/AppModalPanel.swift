import AppKit

@MainActor
enum AppModalPanel {
    static func make(size: NSSize) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .windowBackgroundColor
        panel.level = .modalPanel
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        return panel
    }

    static func run(
        _ panel: NSPanel,
        relativeTo parentWindow: NSWindow? = nil,
        prepare: (() -> Void)? = nil
    ) -> NSApplication.ModalResponse {
        if let parentWindow {
            let parentFrame = parentWindow.frame
            let panelFrame = panel.frame
            panel.setFrameOrigin(NSPoint(
                x: parentFrame.midX - panelFrame.width / 2,
                y: parentFrame.midY - panelFrame.height / 2
            ))
        } else {
            panel.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        prepare?()
        let response = NSApp.runModal(for: panel)
        panel.orderOut(nil)
        return response
    }
}
