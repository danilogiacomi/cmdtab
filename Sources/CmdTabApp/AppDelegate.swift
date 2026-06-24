import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpMenuBar()
        if !PermissionsManager.isAccessibilityTrusted(prompt: true) {
            // The system dialog is now showing. Poll until granted, then
            // continue setup. Real wiring is completed in Task 10.
            waitForAccessibility()
        } else {
            startSwitcher()
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

    private func waitForAccessibility() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            if PermissionsManager.isAccessibilityTrusted(prompt: false) {
                timer.invalidate()
                self?.startSwitcher()
            }
        }
    }

    /// Placeholder; replaced by full wiring in Task 10.
    private func startSwitcher() {
        NSLog("CmdTab: accessibility granted, switcher ready (wiring added in Task 10)")
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
