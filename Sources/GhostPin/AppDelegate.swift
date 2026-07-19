import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let flagIndex = CommandLine.arguments.firstIndex(of: "--selftest"),
           CommandLine.arguments.count > flagIndex + 1 {
            SelfTest.run(outputPath: CommandLine.arguments[flagIndex + 1])
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "GhostPin")
        menu.delegate = self
        statusItem.menu = menu

        HotKeyCenter.shared.register(keyCode: KeyCode.p) { AppDelegate.pinFrontmost() }
        HotKeyCenter.shared.register(keyCode: KeyCode.g) { PinManager.shared.toggleGhostAll() }
        HotKeyCenter.shared.register(keyCode: KeyCode.u) { PinManager.shared.unpinAll() }

        PermissionHelper.ensureScreenRecordingAccess()
    }

    static func pinFrontmost() {
        guard let window = WindowLister.frontmostWindowOfActiveApp() else { return }
        PinManager.shared.toggle(windowID: window.windowID)
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let pinned = PinManager.shared.sessions
        if !pinned.isEmpty {
            menu.addItem(sectionHeader("Pinned — click to unpin"))
            for session in pinned {
                let item = NSMenuItem(title: menuTitle(app: session.appName, title: session.title),
                                      action: #selector(unpinItem(_:)), keyEquivalent: "")
                item.target = self
                item.state = .on
                item.representedObject = session.windowID
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        menu.addItem(sectionHeader("Pin a window"))
        let windows = WindowLister.onScreenWindows().filter { !PinManager.shared.isPinned($0.windowID) }
        if windows.isEmpty {
            let empty = NSMenuItem(title: "No windows found", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for window in windows.prefix(15) {
            let item = NSMenuItem(title: menuTitle(app: window.appName, title: window.title),
                                  action: #selector(pinItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = window.windowID
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let pinFront = NSMenuItem(title: "Pin/Unpin Frontmost Window", action: #selector(pinFrontmostItem), keyEquivalent: "p")
        pinFront.keyEquivalentModifierMask = [.command, .option]
        pinFront.target = self
        menu.addItem(pinFront)

        let ghost = NSMenuItem(title: "Ghost Mode (click-through, all pins)", action: #selector(toggleGhost), keyEquivalent: "g")
        ghost.keyEquivalentModifierMask = [.command, .option]
        ghost.target = self
        ghost.state = PinManager.shared.ghostAll ? .on : .off
        ghost.isEnabled = !pinned.isEmpty
        menu.addItem(ghost)

        let unpinAll = NSMenuItem(title: "Unpin All", action: #selector(unpinAllItem), keyEquivalent: "u")
        unpinAll.keyEquivalentModifierMask = [.command, .option]
        unpinAll.target = self
        unpinAll.isEnabled = !pinned.isEmpty
        menu.addItem(unpinAll)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit GhostPin", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func menuTitle(app: String, title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let combined = trimmed.isEmpty ? app : "\(app) — \(trimmed)"
        return combined.count > 60 ? String(combined.prefix(57)) + "…" : combined
    }

    @objc private func pinItem(_ sender: NSMenuItem) {
        guard let windowID = sender.representedObject as? CGWindowID else { return }
        PinManager.shared.toggle(windowID: windowID)
    }

    @objc private func unpinItem(_ sender: NSMenuItem) {
        guard let windowID = sender.representedObject as? CGWindowID else { return }
        PinManager.shared.toggle(windowID: windowID)
    }

    @objc private func pinFrontmostItem() { AppDelegate.pinFrontmost() }
    @objc private func toggleGhost() { PinManager.shared.toggleGhostAll() }
    @objc private func unpinAllItem() { PinManager.shared.unpinAll() }
}
