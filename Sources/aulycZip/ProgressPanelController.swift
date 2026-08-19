import AppKit

@MainActor
final class ProgressPanelController {
    private var panel: NSPanel?
    private var cancelHandler: (() -> Void)?
    private weak var messageLabel: NSTextField?
    private weak var progressIndicator: NSProgressIndicator?

    func showOperation(
        title: String,
        detail: String,
        onCancel: (() -> Void)? = nil
    ) {
        dismiss()
        cancelHandler = onCancel

        let panel = makePanel(
            size: NSSize(width: 380, height: onCancel == nil ? 132 : 166),
            title: "aulycZip"
        )
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.startAnimation(nil)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingMiddle

        let labels = NSStackView(views: [titleLabel, detailLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 5

        let row = NSStackView(views: [spinner, labels])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        row.translatesAutoresizingMaskIntoConstraints = false

        guard let contentView = panel.contentView else { return }
        contentView.addSubview(row)
        var constraints = [
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
        ]
        if onCancel == nil {
            constraints.append(row.centerYAnchor.constraint(equalTo: contentView.centerYAnchor))
        } else {
            let cancelButton = NSButton(
                title: "取消",
                target: self,
                action: #selector(cancelOperation(_:))
            )
            cancelButton.bezelStyle = .rounded
            cancelButton.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(cancelButton)
            constraints.append(contentsOf: [
                row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 30),
                cancelButton.trailingAnchor.constraint(
                    equalTo: contentView.trailingAnchor,
                    constant: -24
                ),
                cancelButton.topAnchor.constraint(equalTo: row.bottomAnchor, constant: 14),
                cancelButton.widthAnchor.constraint(equalToConstant: 80),
            ])
        }
        NSLayoutConstraint.activate(constraints)
        present(panel, activatingApplication: false)
    }

    func showUpdate(message: String) {
        dismiss()
        let panel = makePanel(
            size: NSSize(width: 390, height: 132),
            title: "正在更新 aulycZip"
        )
        panel.hidesOnDeactivate = false

        let messageLabel = NSTextField(labelWithString: message)
        messageLabel.font = .systemFont(ofSize: 13)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        self.messageLabel = messageLabel

        let progressIndicator = NSProgressIndicator()
        progressIndicator.style = .bar
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 100
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        self.progressIndicator = progressIndicator

        guard let contentView = panel.contentView else { return }
        contentView.addSubview(messageLabel)
        contentView.addSubview(progressIndicator)
        NSLayoutConstraint.activate([
            messageLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            messageLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28),
            progressIndicator.leadingAnchor.constraint(equalTo: messageLabel.leadingAnchor),
            progressIndicator.trailingAnchor.constraint(equalTo: messageLabel.trailingAnchor),
            progressIndicator.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 18),
        ])
        update(message: message, fraction: nil)
        present(panel, activatingApplication: true)
    }

    func update(message: String, fraction: Double?) {
        messageLabel?.stringValue = message
        if let fraction {
            progressIndicator?.isIndeterminate = false
            progressIndicator?.stopAnimation(nil)
            progressIndicator?.doubleValue = min(max(fraction, 0), 1) * 100
        } else {
            progressIndicator?.isIndeterminate = true
            progressIndicator?.startAnimation(nil)
        }
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        cancelHandler = nil
        messageLabel = nil
        progressIndicator = nil
    }

    private func makePanel(size: NSSize, title: String) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        return panel
    }

    private func present(_ panel: NSPanel, activatingApplication: Bool) {
        if activatingApplication {
            NSApp.activate(ignoringOtherApps: true)
        }
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    @objc private func cancelOperation(_ sender: NSButton) {
        sender.isEnabled = false
        cancelHandler?()
    }
}
