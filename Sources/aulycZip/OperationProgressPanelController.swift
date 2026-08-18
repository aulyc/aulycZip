import AppKit

@MainActor
final class OperationProgressPanelController {
    private var panel: NSPanel?
    private var cancelHandler: (() -> Void)?

    func show(
        title: String,
        detail: String,
        onCancel: (() -> Void)? = nil
    ) {
        dismiss()
        cancelHandler = onCancel

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: onCancel == nil ? 132 : 166),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = "aulycZip"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
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
        panel.contentView?.addSubview(row)
        if let contentView = panel.contentView {
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
        }

        panel.center()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        cancelHandler = nil
    }

    @objc private func cancelOperation(_ sender: NSButton) {
        sender.isEnabled = false
        cancelHandler?()
    }
}
