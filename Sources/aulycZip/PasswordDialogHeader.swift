import AppKit

@MainActor
func passwordDialogHeader(
    title: String,
    accessibilityIdentifier: String
) -> NSView {
    let iconView = NSImageView()
    iconView.image = NSApp.applicationIconImage
    iconView.imageScaling = .scaleProportionallyUpOrDown
    iconView.translatesAutoresizingMaskIntoConstraints = false
    iconView.setAccessibilityLabel("aulycZip")

    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
    titleLabel.textColor = .labelColor
    titleLabel.setAccessibilityIdentifier(accessibilityIdentifier)

    let row = NSStackView(views: [iconView, titleLabel])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 10
    row.translatesAutoresizingMaskIntoConstraints = false

    let container = NSView()
    container.addSubview(row)
    NSLayoutConstraint.activate([
        iconView.widthAnchor.constraint(equalToConstant: 30),
        iconView.heightAnchor.constraint(equalToConstant: 30),
        row.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        row.topAnchor.constraint(equalTo: container.topAnchor),
        row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
    return container
}
