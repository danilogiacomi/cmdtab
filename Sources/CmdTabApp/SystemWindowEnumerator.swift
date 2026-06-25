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
    /// Main CGS connection, reused for Space lookups.
    private let cgsConnection = CGSMainConnectionID()

    func snapshot() -> [WindowInfo] {
        var result: [WindowInfo] = []
        var seen = Set<CGWindowID>()
        // The current window = the AXMain window of whatever app is frontmost.
        // CmdTab's overlay is a non-activating panel, so frontmost stays the
        // user's previously focused app while the switcher is open.
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

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
                let minimized = isMinimized(axWindow)
                let fullScreen = isFullScreen(axWindow)
                result.append(WindowInfo(
                    id: wid,
                    pid: pid,
                    appName: appName,
                    title: axTitle(axWindow),
                    isMinimized: minimized,
                    isFullScreen: fullScreen,
                    // App-scoped: macOS hides whole apps (Cmd+H), not individual
                    // windows, so every window of a hidden app reports isHidden.
                    isHidden: app.isHidden,
                    // Suppressed when minimized/full screen — those are the more
                    // specific signal, so the generic "elsewhere" icon is redundant.
                    isOnOtherSpace: !minimized && !fullScreen && isOnOtherSpace(wid),
                    isDialog: isDialog(axWindow),
                    isCurrent: pid == frontmostPID && isMain(axWindow)
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

    private func isDialog(_ element: AXUIElement) -> Bool {
        guard let subrole = axString(element, kAXSubroleAttribute as CFString) else { return false }
        return subrole == (kAXDialogSubrole as String)
            || subrole == (kAXSystemDialogSubrole as String)
    }

    private func isMain(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXMainAttribute as CFString, &value) == .success
        else { return false }
        return (value as? Bool) == true
    }

    /// True when the window lives on a Space other than the active one.
    /// Returns false on any CGS failure (degrade to "not flagged").
    private func isOnOtherSpace(_ wid: CGWindowID) -> Bool {
        let active = CGSGetActiveSpace(cgsConnection)
        guard active != 0 else { return false }
        let windows = [NSNumber(value: wid)] as CFArray
        guard let spaces = CGSCopySpacesForWindows(cgsConnection, Int32(kCGSAllSpacesMask), windows) as? [Int],
              !spaces.isEmpty else { return false }
        return !spaces.contains(Int(active))
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
