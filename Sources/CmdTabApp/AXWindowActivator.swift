import AppKit
import ApplicationServices
import CGSPrivate
import CmdTabCore

final class AXWindowActivator: WindowActivating {
    func activate(_ window: WindowInfo) {
        if let axWindow = axWindow(pid: window.pid, windowID: window.id) {
            // Un-minimize if needed, then raise the specific window.
            AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        }
        NSRunningApplication(processIdentifier: window.pid)?
            .activate()
    }

    private func axWindow(pid: pid_t, windowID: CGWindowID) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let axWindows = value as? [AXUIElement] else { return nil }
        for axWindow in axWindows {
            var wid = CGWindowID(0)
            if _AXUIElementGetWindow(axWindow, &wid) == .success, wid == windowID {
                return axWindow
            }
        }
        return axWindows.first   // fallback: any window of the app
    }
}
