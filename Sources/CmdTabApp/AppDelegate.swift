import AppKit
import CmdTabCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    private let mru = MRUStore()
    private let enumerator = SystemWindowEnumerator()
    private let activator = AXWindowActivator()
    private let monitor = CGEventTapHotkeyMonitor()
    private let overlay = SwitcherOverlay()
    private var controller: SwitcherController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpMenuBar()
        observeFocusChanges()
        if PermissionsManager.isAccessibilityTrusted(prompt: true) {
            startSwitcher()
        } else {
            waitForAccessibility()
        }
    }

    private func setUpMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⌘⇥"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "CmdTab", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit CmdTab", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    /// Keep the MRU list warm by recording every app activation's frontmost window.
    private func observeFocusChanges() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard
                let self,
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            // Record the app's frontmost matching window as most-recently-used.
            if let top = self.enumerator.snapshot().first(where: { $0.pid == app.processIdentifier }) {
                self.mru.recordFocus(top.id)
            }
        }
    }

    private func waitForAccessibility() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            if PermissionsManager.isAccessibilityTrusted(prompt: false) {
                timer.invalidate()
                self?.startSwitcher()
            }
        }
    }

    private func startSwitcher() {
        let controller = SwitcherController(enumerator: enumerator, activator: activator, mru: mru)
        controller.onShow = { [weak self] windows, selected in
            self?.overlay.show(windows, selected: selected)
        }
        controller.onSelectionChange = { [weak self] index in
            self?.overlay.highlight(index)
        }
        controller.onHide = { [weak self] in
            self?.overlay.hide()
        }
        self.controller = controller

        overlay.onHover = { [weak controller] index in controller?.setSelection(index) }
        overlay.onClick = { [weak controller] index in
            controller?.setSelection(index)
            controller?.handle(.commit)
        }

        monitor.onCommand = { [weak controller] command in controller?.handle(command) }
        do {
            try monitor.start()
            NSLog("CmdTab: ready")
        } catch {
            NSLog("CmdTab: event tap failed — enable Input Monitoring for CmdTab. \(error)")
        }
    }

    @objc private func quit() {
        monitor.stop()
        NSApp.terminate(nil)
    }
}
