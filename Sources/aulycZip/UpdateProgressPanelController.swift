import AppKit

@MainActor
final class UpdateProgressPanelController {
    private var panel: NSPanel?
    private weak var messageLabel: NSTextField?
    private weak var progressIndicator: NSProgressIndicator?

    func show(message: String) {
        NSApp.activate(ignoringOtherApps: true)
        if panel == nil {
            panel = makePanel()
        }
        update(message: message, fraction: nil)
        panel?.center()
        panel?.makeKeyAndOrderFront(nil)
    }

    func update(message: String, fraction: Double?) {
        messageLabel?.stringValue = message
        if let fraction {
            progressIndicator?.isIndeterminate = false
            progressIndicator?.doubleValue = min(max(fraction, 0), 1) * 100
        } else {
            progressIndicator?.isIndeterminate = true
            progressIndicator?.startAnimation(nil)
        }
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 390, height: 132),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = "正在更新 aulycZip"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let message = NSTextField(labelWithString: "正在准备更新")
        message.font = .systemFont(ofSize: 13)
        message.textColor = .secondaryLabelColor
        message.lineBreakMode = .byTruncatingTail
        message.translatesAutoresizingMaskIntoConstraints = false
        messageLabel = message

        let progress = NSProgressIndicator()
        progress.style = .bar
        progress.minValue = 0
        progress.maxValue = 100
        progress.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator = progress

        let content = NSView()
        content.addSubview(message)
        content.addSubview(progress)
        panel.contentView = content
        NSLayoutConstraint.activate([
            message.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            message.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            message.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            progress.leadingAnchor.constraint(equalTo: message.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: message.trailingAnchor),
            progress.topAnchor.constraint(equalTo: message.bottomAnchor, constant: 18),
        ])
        return panel
    }
}
