import AppKit
import ApplicationServices
import CGSPrivate
import CmdTabCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let legend = LegendWindowController()

    private let mru = MRUStore()
    private let enumerator = SystemWindowEnumerator()
    private let activator = AXWindowActivator()
    private let monitor = CGEventTapHotkeyMonitor()
    private let overlay = SwitcherOverlay()
    private var controller: SwitcherController?
    private var focusObserver: NSObjectProtocol?

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
        let legendItem = NSMenuItem(title: "Window State Icons…", action: #selector(showLegend), keyEquivalent: "")
        legendItem.target = self
        menu.addItem(legendItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit CmdTab", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    /// Keep the MRU list warm by recording every app activation's frontmost window.
    private func observeFocusChanges() {
        focusObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard
                let self,
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            // Record the app's AX-focused window as most-recently-used.
            if let wid = self.focusedWindowID(pid: app.processIdentifier) {
                self.mru.recordFocus(wid)
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
        guard controller == nil else { return }
        let controller = SwitcherController(enumerator: enumerator, activator: activator, mru: mru)
        controller.onShow = { [weak self] windows, selected in
            self?.overlay.show(windows, selected: selected)
        }
        controller.onSelectionChange = { [weak self] index in
            self?.overlay.highlight(index)
        }
        controller.onHide = { [weak self] in
            self?.overlay.hide()
            // Keep the key monitor's gesture mirror in sync: a mouse-click
            // commit hides the overlay without the monitor seeing any keys.
            self?.monitor.overlayDidHide()
        }
        self.controller = controller

        overlay.onHover = { [weak controller] index in controller?.setSelection(index) }
        overlay.onClick = { [weak controller] index in
            controller?.setSelection(index)
            controller?.handle(.commit)
        }

        monitor.onCommand = { [weak controller] command in controller?.handle(command) }
        monitor.isMouseInsideOverlay = { [weak self] in self?.overlay.containsMouse() ?? false }
        do {
            try monitor.start()
            NSLog("CmdTab: ready")
        } catch {
            NSLog("CmdTab: event tap failed — enable Input Monitoring for CmdTab. \(error)")
        }
    }

    /// The CGWindowID of the given app's currently-focused AX window, if available.
    private func focusedWindowID(pid: pid_t) -> CGWindowID? {
        let appElement = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focused) == .success,
              let focusedValue = focused,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else { return nil }
        let axWindow = focusedValue as! AXUIElement
        var wid = CGWindowID(0)
        guard _AXUIElementGetWindow(axWindow, &wid) == .success else { return nil }
        return wid
    }

    @objc private func showLegend() {
        legend.show()
    }

    @objc private func quit() {
        monitor.stop()
        if let focusObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(focusObserver)
        }
        NSApp.terminate(nil)
    }
}
