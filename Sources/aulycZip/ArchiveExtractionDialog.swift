import AppKit
import ZipCore
import aulycZipAppSupport

@MainActor
final class ArchiveExtractionLocationController: NSObject {
    private let archiveURL: URL
    private(set) var parentDirectoryURL: URL
    private(set) var destinationURL: URL
    private let outputDirectoryControl: ArchivePathDisplayControl
    private weak var directoryPickerButton: NSButton?
    private var createsIndependentFolder = true

    var destinationPolicy: ZipExtractionDestinationPolicy {
        createsIndependentFolder ? .createNewDirectory : .mergeIntoExistingDirectory
    }

    init(archiveURL: URL) {
        self.archiveURL = archiveURL
        parentDirectoryURL = archiveURL.deletingLastPathComponent()
        destinationURL = ArchiveExtractionDestination.resolve(
            archiveURL: archiveURL,
            selectedParent: parentDirectoryURL,
            createsIndependentFolder: true
        )
        outputDirectoryControl = ArchivePathDisplayControl(
            path: destinationURL.path,
            accessibilityIdentifier: "archive-extraction-output-directory"
        )
        super.init()
    }

    func makeOutputDirectoryControl() -> NSView {
        let chooseButton = NSButton(
            image: NSImage(
                systemSymbolName: "folder",
                accessibilityDescription: "选择输出位置"
            ) ?? NSImage(),
            target: self,
            action: #selector(chooseDestinationDirectory(_:))
        )
        chooseButton.bezelStyle = .rounded
        chooseButton.controlSize = .regular
        chooseButton.imagePosition = .imageOnly
        chooseButton.imageScaling = .scaleProportionallyDown
        chooseButton.contentTintColor = .secondaryLabelColor
        chooseButton.toolTip = "选择解压文件夹的保存位置"
        chooseButton.setAccessibilityLabel("选择输出位置")
        chooseButton.setAccessibilityIdentifier("archive-extraction-directory-picker")
        directoryPickerButton = chooseButton

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        outputDirectoryControl.translatesAutoresizingMaskIntoConstraints = false
        chooseButton.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(outputDirectoryControl)
        row.addSubview(chooseButton)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 28),
            outputDirectoryControl.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            outputDirectoryControl.trailingAnchor.constraint(
                equalTo: chooseButton.leadingAnchor,
                constant: -8
            ),
            outputDirectoryControl.topAnchor.constraint(equalTo: row.topAnchor),
            outputDirectoryControl.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            chooseButton.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            chooseButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            chooseButton.widthAnchor.constraint(equalToConstant: 28),
            chooseButton.heightAnchor.constraint(equalToConstant: 28),
        ])
        return row
    }

    func makeIndependentFolderCheckbox() -> NSButton {
        let checkbox = NSButton(
            checkboxWithTitle: "解压到独立文件夹",
            target: self,
            action: #selector(toggleIndependentFolder(_:))
        )
        checkbox.state = .on
        checkbox.font = .systemFont(ofSize: 13)
        checkbox.toolTip = "取消勾选后，将直接解压到 ZIP 所在目录"
        checkbox.setAccessibilityIdentifier("archive-extraction-independent-folder")
        return checkbox
    }

    func validateSelection() -> FinderArchivePasswordValidation? {
        let directory = createsIndependentFolder ? parentDirectoryURL : destinationURL
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(
            atPath: directory.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            return FinderArchivePasswordValidation(
                title: "无法使用这个输出位置",
                message: "请选择一个仍然存在且可以访问的文件夹。",
                buttonTitle: "重新选择",
                firstResponder: nil
            )
        }
        return nil
    }

    @objc private func chooseDestinationDirectory(_ sender: NSButton) {
        guard let parentWindow = sender.window else { return }

        let panel = NSOpenPanel()
        panel.title = "选择解压文件夹的保存位置"
        panel.prompt = "选择此目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = parentDirectoryURL
        panel.beginSheetModal(for: parentWindow) { [weak self] response in
            guard response == .OK, let directory = panel.url, let self else { return }
            parentDirectoryURL = directory
            refreshDestination()
        }
    }

    @objc private func toggleIndependentFolder(_ sender: NSButton) {
        createsIndependentFolder = sender.state == .on
        directoryPickerButton?.isEnabled = createsIndependentFolder
        refreshDestination()
    }

    private func refreshDestination() {
        destinationURL = ArchiveExtractionDestination.resolve(
            archiveURL: archiveURL,
            selectedParent: parentDirectoryURL,
            createsIndependentFolder: createsIndependentFolder
        )
        outputDirectoryControl.path = destinationURL.path
    }
}
