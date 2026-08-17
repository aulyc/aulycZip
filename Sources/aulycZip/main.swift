import AppKit

@MainActor
private func installMinimalEditMenu(on app: NSApplication) {
    let mainMenu = NSMenu()
    let editMenuItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
    let editMenu = NSMenu(title: "编辑")

    editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
    let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

    editMenuItem.submenu = editMenu
    mainMenu.addItem(editMenuItem)
    app.mainMenu = mainMenu
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated {
    installMinimalEditMenu(on: app)
    return AppDelegate()
}
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
