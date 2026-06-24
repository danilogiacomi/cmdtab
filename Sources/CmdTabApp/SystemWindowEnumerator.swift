import AppKit
import CoreGraphics
import ApplicationServices
import CGSPrivate
import CmdTabCore

final class SystemWindowEnumerator: WindowEnumerating {
    /// Our own process ID, so we never list CmdTab's own windows.
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    func snapshot() -> [WindowInfo] {
        var result: [WindowInfo] = []
        var seen = Set<CGWindowID>()

        result.append(contentsOf: cgWindowListWindows(seen: &seen))
        result.append(contentsOf: minimizedWindows(seen: &seen))
        return result
    }

    // MARK: CGWindowList (normal + off-screen across all Spaces)

    private func cgWindowListWindows(seen: inout Set<CGWindowID>) -> [WindowInfo] {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var out: [WindowInfo] = []
        for dict in raw {
            guard
                let layer = dict[kCGWindowLayer as String] as? Int, layer == 0,
                let wid = dict[kCGWindowNumber as String] as? CGWindowID,
                let pid = dict[kCGWindowOwnerPID as String] as? pid_t,
                pid != ownPID
            else { continue }

            // Require a real, on-app window: must have an owner name; skip
            // zero-area utility surfaces.
            let appName = (dict[kCGWindowOwnerName as String] as? String) ?? ""
            if appName.isEmpty { continue }
            if let bounds = dict[kCGWindowBounds as String] as? [String: CGFloat],
               (bounds["Width"] ?? 0) < 40 && (bounds["Height"] ?? 0) < 40 { continue }

            guard !seen.contains(wid) else { continue }
            seen.insert(wid)
            let title = (dict[kCGWindowName as String] as? String) ?? ""
            out.append(WindowInfo(id: wid, pid: pid, appName: appName, title: title, isMinimized: false))
        }
        return out
    }

    // MARK: Accessibility (minimized windows, which CGWindowList omits)

    private func minimizedWindows(seen: inout Set<CGWindowID>) -> [WindowInfo] {
        var out: [WindowInfo] = []
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != ownPID {
            let pid = app.processIdentifier
            let appElement = AXUIElementCreateApplication(pid)

            var windowsValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
                  let axWindows = windowsValue as? [AXUIElement] else { continue }

            for axWindow in axWindows {
                guard isMinimized(axWindow) else { continue }
                var wid = CGWindowID(0)
                guard _AXUIElementGetWindow(axWindow, &wid) == .success, !seen.contains(wid) else { continue }
                seen.insert(wid)
                out.append(WindowInfo(
                    id: wid,
                    pid: pid,
                    appName: app.localizedName ?? "",
                    title: axTitle(axWindow),
                    isMinimized: true
                ))
            }
        }
        return out
    }

    private func isMinimized(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &value) == .success
        else { return false }
        return (value as? Bool) == true
    }

    private func axTitle(_ element: AXUIElement) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success
        else { return "" }
        return (value as? String) ?? ""
    }
}
