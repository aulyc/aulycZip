import AppKit

@MainActor
final class WorkflowCompletionDialog: NSObject {
    private static let panelWidth: CGFloat = 260
    private static let contentWidth: CGFloat = 228
    private static let messageFont = NSFont.systemFont(ofSize: 13)

    private let panel: NSPanel

    init(title: String, message: String) {
        let messageHeight = max(
            17,
            ceil(
                (message as NSString).boundingRect(
                    with: NSSize(
                        width: Self.contentWidth,
                        height: .greatestFiniteMagnitude
                    ),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: Self.messageFont]
                ).height
            )
        )
        let panelHeight = 162 + messageHeight
        panel = AppModalPanel.make(
            size: NSSize(width: Self.panelWidth, height: panelHeight)
        )
        super.init()

        let header = appDialogHeader(
            title: title,
            accessibilityIdentifier: "workflow-completion-title"
        )

        let messageLabel = NSTextField(wrappingLabelWithString: message)
        messageLabel.font = Self.messageFont
        messageLabel.textColor = .labelColor
        messageLabel.lineBreakMode = .byCharWrapping
        messageLabel.maximumNumberOfLines = 0
        messageLabel.preferredMaxLayoutWidth = Self.contentWidth

        let revealButton = NSButton(
            title: "在 Finder 中显示",
            target: self,
            action: #selector(reveal(_:))
        )
        revealButton.bezelStyle = .rounded
        revealButton.controlSize = .large
        revealButton.keyEquivalent = "\r"

        let doneButton = NSButton(
            title: "完成",
            target: self,
            action: #selector(done(_:))
        )
        doneButton.bezelStyle = .rounded
        doneButton.controlSize = .large
        doneButton.keyEquivalent = "\u{1b}"

        let stack = NSStackView(views: [
            header,
            messageLabel,
            revealButton,
            doneButton,
        ])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.setCustomSpacing(12, after: header)
        stack.setCustomSpacing(16, after: messageLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false

        guard let contentView = panel.contentView else { return }
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            header.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            messageLabel.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            messageLabel.heightAnchor.constraint(equalToConstant: messageHeight),
            revealButton.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            doneButton.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            revealButton.heightAnchor.constraint(equalToConstant: 32),
            doneButton.heightAnchor.constraint(equalToConstant: 32),
        ])
        panel.defaultButtonCell = revealButton.cell as? NSButtonCell
    }

    func runModal() -> NSApplication.ModalResponse {
        AppModalPanel.run(panel)
    }

    @objc private func reveal(_ sender: NSButton) {
        NSApp.stopModal(withCode: .alertFirstButtonReturn)
    }

    @objc private func done(_ sender: NSButton) {
        NSApp.stopModal(withCode: .alertSecondButtonReturn)
    }
}
