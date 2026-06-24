import AppKit
import CoreGraphics
import ApplicationServices
import CGSPrivate
import CmdTabCore

/// Enumerates real, switchable windows via the Accessibility API — one entry per
/// window, deduplicated by `CGWindowID`.
///
/// We use AX (`kAXWindowsAttribute`) rather than `CGWindowListCopyWindowInfo`
/// because CGWindowList's layer-0 set is full of non-window helper surfaces
/// (toolbar strips, UI-service overlays) and its titles are empty without
/// Screen Recording permission — both of which made the list show apparent
/// duplicates. AX returns each app's actual windows (across Spaces, including
/// minimized) with real titles, using only the Accessibility access we already
/// require. `_AXUIElementGetWindow` maps each AX window to its `CGWindowID` so
/// the rest of the app (MRU, activation) keys on a stable identity.
final class SystemWindowEnumerator: WindowEnumerating {
    /// Our own process ID, so we never list CmdTab's own windows.
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    func snapshot() -> [WindowInfo] {
        var result: [WindowInfo] = []
        var seen = Set<CGWindowID>()

        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != ownPID {
            let pid = app.processIdentifier
            let appName = app.localizedName ?? ""
            let appElement = AXUIElementCreateApplication(pid)

            var windowsValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
                  let axWindows = windowsValue as? [AXUIElement] else { continue }

            for axWindow in axWindows {
                guard isSwitchableWindow(axWindow) else { continue }
                var wid = CGWindowID(0)
                guard _AXUIElementGetWindow(axWindow, &wid) == .success, wid != 0, !seen.contains(wid) else { continue }
                seen.insert(wid)
                result.append(WindowInfo(
                    id: wid,
                    pid: pid,
                    appName: appName,
                    title: axTitle(axWindow),
                    isMinimized: isMinimized(axWindow),
                    isFullScreen: isFullScreen(axWindow),
                    isHidden: app.isHidden
                ))
            }
        }
        return result
    }

    /// A real, user-switchable window: reports the window role, and (if it
    /// declares a subrole) is a standard window or dialog — not a palette,
    /// popover, or other auxiliary surface. Windows without a subrole are kept.
    private func isSwitchableWindow(_ element: AXUIElement) -> Bool {
        guard axString(element, kAXRoleAttribute as CFString) == (kAXWindowRole as String) else { return false }
        guard let subrole = axString(element, kAXSubroleAttribute as CFString), !subrole.isEmpty else {
            return true
        }
        return subrole == (kAXStandardWindowSubrole as String)
            || subrole == (kAXDialogSubrole as String)
            || subrole == (kAXSystemDialogSubrole as String)
    }

    private func isMinimized(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &value) == .success
        else { return false }
        return (value as? Bool) == true
    }

    private func isFullScreen(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXFullScreen" as CFString, &value) == .success
        else { return false }
        return (value as? Bool) == true
    }

    private func axTitle(_ element: AXUIElement) -> String {
        axString(element, kAXTitleAttribute as CFString) ?? ""
    }

    private func axString(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }
}
