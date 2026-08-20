import AppKit

@MainActor
private final class FocusBorderBox: NSBox {
    private var isFocused = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        boxType = .custom
        borderWidth = 1
        cornerRadius = 5
        borderColor = .separatorColor
        fillColor = .controlBackgroundColor
        titlePosition = .noTitle
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setFocused(_ focused: Bool) {
        guard isFocused != focused else { return }
        isFocused = focused
        updateBorder()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorder()
    }

    private func updateBorder() {
        borderWidth = 1
        borderColor = isFocused ? .keyboardFocusIndicatorColor : .separatorColor
        needsDisplay = true
    }
}

@MainActor
final class ArchiveFileNameControl: NSView, NSTextFieldDelegate {
    private let fieldBackground = FocusBorderBox(frame: .zero)
    private let directoryLabel = NSTextField(frame: .zero)
    private let baseNameField = NSTextField(frame: .zero)
    private let suffixLabel = NSTextField(frame: .zero)
    private var baseNameWidthConstraint: NSLayoutConstraint!

    var directoryPath: String {
        get {
            let value = directoryLabel.stringValue
            return value == "/" ? value : String(value.dropLast())
        }
        set {
            let path = newValue == "/" ? "/" : newValue + "/"
            directoryLabel.stringValue = path
            directoryLabel.toolTip = newValue
            refreshToolTip()
        }
    }

    var baseName: String {
        get { baseNameField.stringValue }
        set {
            baseNameField.stringValue = normalizedBaseName(newValue)
            updateBaseNameWidth()
            refreshToolTip()
        }
    }

    init(baseName: String) {
        super.init(frame: .zero)

        baseNameField.isBezeled = false
        baseNameField.drawsBackground = false
        baseNameField.isEditable = true
        baseNameField.isSelectable = true
        baseNameField.focusRingType = .none
        baseNameField.font = .systemFont(ofSize: 13)
        baseNameField.maximumNumberOfLines = 1
        baseNameField.placeholderString = "输出文件名"
        baseNameField.stringValue = normalizedBaseName(baseName)
        baseNameField.delegate = self
        baseNameField.toolTip = "可以修改文件名；.zip 扩展名固定，不可修改"
        baseNameField.setAccessibilityLabel("输出文件名，不含固定的 .zip 扩展名")
        baseNameField.setAccessibilityIdentifier("archive-output-file-base-name")
        updateBaseNamePresentation(isEditing: false)

        directoryLabel.font = .systemFont(ofSize: 13)
        directoryLabel.isBezeled = false
        directoryLabel.drawsBackground = false
        directoryLabel.isEditable = false
        directoryLabel.isSelectable = false
        directoryLabel.focusRingType = .none
        directoryLabel.textColor = .secondaryLabelColor
        directoryLabel.lineBreakMode = .byTruncatingMiddle
        directoryLabel.maximumNumberOfLines = 1
        directoryLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        directoryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        suffixLabel.font = .systemFont(ofSize: 13, weight: .medium)
        suffixLabel.stringValue = ".zip"
        suffixLabel.isBezeled = false
        suffixLabel.drawsBackground = false
        suffixLabel.isEditable = false
        suffixLabel.isSelectable = false
        suffixLabel.focusRingType = .none
        suffixLabel.textColor = .secondaryLabelColor
        suffixLabel.alignment = .left
        suffixLabel.toolTip = "ZIP 扩展名固定，不可修改"

        let stack = NSStackView(views: [directoryLabel, baseNameField, suffixLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 0
        stack.setCustomSpacing(4, after: directoryLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fieldBackground)
        addSubview(stack)

        baseNameField.setContentHuggingPriority(.required, for: .horizontal)
        baseNameField.setContentCompressionResistancePriority(.required, for: .horizontal)
        suffixLabel.setContentHuggingPriority(.required, for: .horizontal)
        suffixLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        baseNameWidthConstraint = baseNameField.widthAnchor.constraint(
            equalToConstant: preferredBaseNameWidth()
        )
        baseNameWidthConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([
            fieldBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            fieldBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            fieldBackground.topAnchor.constraint(equalTo: topAnchor),
            fieldBackground.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.heightAnchor.constraint(equalToConstant: 16),
            directoryLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.5),
            baseNameWidthConstraint,
            baseNameField.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.62),
            directoryLabel.heightAnchor.constraint(equalTo: stack.heightAnchor),
            baseNameField.heightAnchor.constraint(equalTo: stack.heightAnchor),
            suffixLabel.heightAnchor.constraint(equalTo: stack.heightAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func controlTextDidChange(_ notification: Notification) {
        let normalized = normalizedBaseName(baseNameField.stringValue)
        if normalized != baseNameField.stringValue {
            baseNameField.stringValue = normalized
        }
        updateBaseNameWidth()
        refreshToolTip()
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        updateBaseNamePresentation(isEditing: true)
        fieldBackground.setFocused(true)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        updateBaseNamePresentation(isEditing: false)
        fieldBackground.setFocused(false)
    }

    override func becomeFirstResponder() -> Bool {
        window?.makeFirstResponder(baseNameField) ?? false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0, bounds.contains(point) else { return nil }
        return self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        guard window?.makeFirstResponder(baseNameField) == true else { return }

        let pointInField = baseNameField.convert(event.locationInWindow, from: nil)
        if baseNameField.bounds.contains(pointInField) {
            baseNameField.mouseDown(with: event)
            return
        }

        guard let editor = baseNameField.currentEditor() as? NSTextView else { return }
        // The path and suffix are read-only parts of one visual field. Clicking the
        // path starts at the beginning; clicking the suffix or trailing area moves
        // to the end, while keeping the fixed .zip outside the editable selection.
        let location = pointInField.x < baseNameField.bounds.minX
            ? 0
            : baseNameField.stringValue.utf16.count
        let range = NSRange(location: location, length: 0)
        editor.setSelectedRange(range)
        editor.scrollRangeToVisible(range)
    }

    private func normalizedBaseName(_ value: String) -> String {
        value.lowercased().hasSuffix(".zip") ? String(value.dropLast(4)) : value
    }

    private func updateBaseNameWidth() {
        baseNameWidthConstraint?.constant = preferredBaseNameWidth()
    }

    private func updateBaseNamePresentation(isEditing: Bool) {
        baseNameField.lineBreakMode = isEditing ? .byClipping : .byTruncatingMiddle
        baseNameField.cell?.usesSingleLineMode = true
        baseNameField.cell?.wraps = false
        baseNameField.cell?.isScrollable = isEditing
        baseNameField.needsDisplay = true
    }

    private func preferredBaseNameWidth() -> CGFloat {
        let visibleText = baseNameField.stringValue.isEmpty
            ? (baseNameField.placeholderString ?? "")
            : baseNameField.stringValue
        let font = baseNameField.font ?? .systemFont(ofSize: 13)
        let textWidth = ceil(
            (visibleText as NSString).size(withAttributes: [.font: font]).width
        )
        return min(244, max(12, textWidth + 2))
    }

    private func refreshToolTip() {
        let directory = directoryLabel.stringValue
        toolTip = directory.isEmpty ? nil : directory + baseNameField.stringValue + ".zip"
    }
}

@MainActor
final class ArchivePathDisplayControl: NSView {
    private let fieldBackground = FocusBorderBox(frame: .zero)
    private let pathLabel = NSTextField(frame: .zero)

    var path: String {
        get { pathLabel.stringValue }
        set {
            pathLabel.stringValue = newValue
            pathLabel.toolTip = newValue
        }
    }

    init(path: String, accessibilityIdentifier: String) {
        super.init(frame: .zero)

        pathLabel.font = .systemFont(ofSize: 13)
        pathLabel.isBezeled = false
        pathLabel.drawsBackground = false
        pathLabel.isEditable = false
        pathLabel.isSelectable = true
        pathLabel.focusRingType = .none
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.maximumNumberOfLines = 1
        pathLabel.cell?.usesSingleLineMode = true
        pathLabel.stringValue = path
        pathLabel.toolTip = path
        pathLabel.setAccessibilityLabel("输出文件夹")
        pathLabel.setAccessibilityIdentifier(accessibilityIdentifier)
        pathLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(fieldBackground)
        addSubview(pathLabel)
        NSLayoutConstraint.activate([
            fieldBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            fieldBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            fieldBackground.topAnchor.constraint(equalTo: topAnchor),
            fieldBackground.bottomAnchor.constraint(equalTo: bottomAnchor),
            pathLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            pathLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            pathLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            pathLabel.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class PasswordEntryControl: NSView {
    private let fieldBackground = FocusBorderBox(frame: .zero)
    private let secureField = NSSecureTextField(frame: .zero)
    private let visibleField = NSTextField(frame: .zero)
    private let secureFocusDelegate = ThinFocusTextFieldDelegate()
    private let visibleFocusDelegate = ThinFocusTextFieldDelegate()
    private let visibilityButton = NSButton(frame: .zero)

    var stringValue: String {
        get { activeField.stringValue }
        set {
            secureField.stringValue = newValue
            visibleField.stringValue = isPasswordVisible ? newValue : ""
        }
    }

    var isPasswordVisible = false {
        didSet {
            guard isPasswordVisible != oldValue else { return }
            switchPasswordVisibility()
            updateVisibilityButton()
        }
    }

    private var activeField: NSTextField {
        isPasswordVisible ? visibleField : secureField
    }

    init(placeholder: String, value: String, visibilityIdentifier: String) {
        super.init(frame: .zero)

        configure(field: secureField, placeholder: placeholder, value: value)
        configure(field: visibleField, placeholder: placeholder, value: "")
        secureField.delegate = secureFocusDelegate
        visibleField.delegate = visibleFocusDelegate
        visibleField.isHidden = true

        secureFocusDelegate.onFocusChanged = { [weak self] focused in
            self?.fieldBackground.setFocused(focused)
        }
        visibleFocusDelegate.onFocusChanged = { [weak self] focused in
            self?.fieldBackground.setFocused(focused)
        }

        visibilityButton.target = self
        visibilityButton.action = #selector(togglePasswordVisibility(_:))
        visibilityButton.isBordered = false
        visibilityButton.bezelStyle = .accessoryBarAction
        visibilityButton.imagePosition = .imageOnly
        visibilityButton.imageScaling = .scaleProportionallyDown
        visibilityButton.contentTintColor = .secondaryLabelColor
        visibilityButton.refusesFirstResponder = true
        visibilityButton.setAccessibilityIdentifier(visibilityIdentifier)
        visibilityButton.translatesAutoresizingMaskIntoConstraints = false
        updateVisibilityButton()

        addSubview(fieldBackground)
        addSubview(secureField)
        addSubview(visibleField)
        addSubview(visibilityButton)
        NSLayoutConstraint.activate([
            fieldBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            fieldBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            fieldBackground.topAnchor.constraint(equalTo: topAnchor),
            fieldBackground.bottomAnchor.constraint(equalTo: bottomAnchor),
            secureField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            secureField.trailingAnchor.constraint(equalTo: visibilityButton.leadingAnchor, constant: -4),
            secureField.centerYAnchor.constraint(equalTo: centerYAnchor),
            secureField.heightAnchor.constraint(equalToConstant: 16),
            visibleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            visibleField.trailingAnchor.constraint(equalTo: visibilityButton.leadingAnchor, constant: -4),
            visibleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            visibleField.heightAnchor.constraint(equalToConstant: 16),
            visibilityButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            visibilityButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            visibilityButton.widthAnchor.constraint(equalToConstant: 22),
            visibilityButton.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func becomeFirstResponder() -> Bool {
        focus()
    }

    @discardableResult
    func focus() -> Bool {
        let focused = window?.makeFirstResponder(activeField) ?? false
        if focused {
            (isPasswordVisible ? visibleFocusDelegate : secureFocusDelegate)
                .setFocusedAppearance(true)
        }
        return focused
    }

    @objc private func togglePasswordVisibility(_ sender: NSButton) {
        isPasswordVisible.toggle()
    }

    private func updateVisibilityButton() {
        let title = isPasswordVisible ? "隐藏密码" : "显示密码"
        let symbolName = isPasswordVisible ? "eye.slash" : "eye"
        visibilityButton.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: title
        )
        visibilityButton.toolTip = title
        visibilityButton.setAccessibilityLabel(title)
    }

    private func configure(field: NSTextField, placeholder: String, value: String) {
        // Hidden mode remains a native NSSecureTextField. The visible peer is also
        // a native AppKit text field and exists only for an explicit reveal action.
        field.translatesAutoresizingMaskIntoConstraints = false
        field.focusRingType = .none
        field.isBezeled = false
        field.drawsBackground = false
        field.isEditable = true
        field.isSelectable = true
        field.font = .systemFont(ofSize: 13)
        field.placeholderString = placeholder
        field.stringValue = value
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
    }

    private func switchPasswordVisibility() {
        let previousField = isPasswordVisible ? secureField : visibleField
        let nextField = activeField
        let currentValue = previousField.stringValue
        let previousEditor = previousField.currentEditor() as? NSTextView
        let selectedRange = previousEditor?.selectedRange()

        if isPasswordVisible {
            visibleField.stringValue = currentValue
        } else {
            secureField.stringValue = currentValue
        }
        secureField.isHidden = isPasswordVisible
        visibleField.isHidden = !isPasswordVisible
        defer {
            if !isPasswordVisible {
                visibleField.stringValue = ""
            }
        }

        guard previousEditor != nil, window?.makeFirstResponder(nextField) == true else {
            return
        }
        if let selectedRange,
           let nextEditor = nextField.currentEditor() as? NSTextView {
            nextEditor.setSelectedRange(selectedRange)
            nextEditor.scrollRangeToVisible(selectedRange)
        }
    }
}

private final class ThinFocusTextFieldDelegate: NSObject, NSTextFieldDelegate {
    private var isEditing = false
    var onFocusChanged: ((Bool) -> Void)?

    func controlTextDidBeginEditing(_ notification: Notification) {
        setFocusedAppearance(true)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        setFocusedAppearance(false)
    }

    func setFocusedAppearance(_ focused: Bool) {
        guard isEditing != focused else { return }
        isEditing = focused
        onFocusChanged?(focused)
    }
}
