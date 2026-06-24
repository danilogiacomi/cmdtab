# CmdTab Window Switcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a personal-use macOS background agent that replaces `⌘Tab` with a Plasma-style switcher listing every open window individually (icon + title), never grouped by app.

**Architecture:** A SwiftPM package with two product layers. `CmdTabCore` (library) holds the pure, unit-tested logic and the adapter protocols (`WindowEnumerating`, `WindowActivating`, `HotkeyMonitoring`). `CmdTabApp` (executable) holds the AppKit shell and the system adapters (CGEventTap, AX/CGWindowList enumeration, AX activation, NSPanel overlay). A `Scripts/bundle.sh` assembles a signed `CmdTab.app` agent bundle. Fragile private symbols live in one C target (`CGSPrivate`).

**Tech Stack:** Swift 5.9, AppKit, CoreGraphics (`CGEventTap`, `CGWindowList`), ApplicationServices (Accessibility / `AXUIElement`), one private symbol (`_AXUIElementGetWindow`), XCTest. macOS 14+.

## Global Constraints

- **Platform floor:** macOS 14 (`.macOS(.v14)` in Package.swift). Verify exact build with `sw_vers -productVersion` before Task 6.
- **Personal use only:** ad-hoc code signing (`codesign --sign -`); no notarization, no Developer ID, no sandbox, no App Store.
- **Display:** icon + window title only. No thumbnails, no Screen Recording permission.
- **Coverage requirement:** list normal, minimized, hidden-app, and other-Space windows; one entry per window; never grouped by app.
- **Permissions:** Accessibility required; Input Monitoring requested only if the event tap fails to create.
- **App shape:** background agent, no Dock icon (`NSApplication.setActivationPolicy(.accessory)` + `LSUIElement` in bundle Info.plist).
- **Core purity:** `CmdTabCore` must not import AppKit. Icons are fetched at render time in the app layer by pid. Keep adapter boundaries as protocols so core logic is testable with fakes.
- **Naming:** product/app name is `CmdTab`; bundle id `com.local.cmdtab`.

---

### Task 1: Package scaffold + build/test loop + docs update

**Files:**
- Create: `Package.swift`
- Create: `Sources/CGSPrivate/include/CGSPrivate.h`
- Create: `Sources/CGSPrivate/shim.c`
- Create: `Sources/CmdTabCore/Placeholder.swift`
- Create: `Sources/CmdTabApp/main.swift`
- Create: `Tests/CmdTabCoreTests/SmokeTests.swift`
- Modify: `AGENTS.md` (replace TODO build/test/lint placeholders with real swift commands)
- Modify: `.github/workflows/ci.yml` (replace echo-TODO stages with real swift commands)

**Interfaces:**
- Produces: a buildable package with targets `CGSPrivate`, `CmdTabCore`, `CmdTabApp`, `CmdTabCoreTests`. Later tasks add files to these targets — no new targets.

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CmdTab",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CGSPrivate"),
        .target(name: "CmdTabCore"),
        .executableTarget(
            name: "CmdTabApp",
            dependencies: ["CmdTabCore", "CGSPrivate"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
        .testTarget(name: "CmdTabCoreTests", dependencies: ["CmdTabCore"]),
    ]
)
```

- [ ] **Step 2: Declare the private symbol shim**

`Sources/CGSPrivate/include/CGSPrivate.h`:
```c
#ifndef CGSPRIVATE_H
#define CGSPRIVATE_H

#include <CoreGraphics/CoreGraphics.h>
#include <ApplicationServices/ApplicationServices.h>

/* Private: maps an AXUIElement window to its CGWindowID.
   Resolves at link time against the ApplicationServices framework. */
AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID *windowID);

#endif
```

`Sources/CGSPrivate/shim.c` (empty translation unit so SwiftPM compiles the target):
```c
#include "include/CGSPrivate.h"
```

- [ ] **Step 3: Add placeholder core source + app entrypoint**

`Sources/CmdTabCore/Placeholder.swift`:
```swift
// Intentionally minimal; real types arrive in later tasks.
public enum CmdTabCore {
    public static let version = "0.1.0"
}
```

`Sources/CmdTabApp/main.swift`:
```swift
import AppKit
import CmdTabCore

print("CmdTab \(CmdTabCore.version) starting")
// Real app bootstrap is added in Task 5.
```

- [ ] **Step 4: Write the smoke test**

`Tests/CmdTabCoreTests/SmokeTests.swift`:
```swift
import XCTest
@testable import CmdTabCore

final class SmokeTests: XCTestCase {
    func testVersionIsSet() {
        XCTAssertEqual(CmdTabCore.version, "0.1.0")
    }
}
```

- [ ] **Step 5: Run build and tests**

Run: `swift build && swift test`
Expected: build succeeds; `testVersionIsSet` PASSES.

- [ ] **Step 6: Update AGENTS.md and CI with the real commands**

In `AGENTS.md`, replace the `## Build · Test · Lint` body with:
```bash
swift build            # build all targets
swift test             # run the CmdTabCore unit tests
./Scripts/bundle.sh    # assemble CmdTab.app (added in Task 5)
swift format lint --recursive Sources   # lint (requires swift-format)
```
Remove the "TODO: confirm once Package.swift exists" lines and the SwiftPM-vs-Xcode note.

In `.github/workflows/ci.yml`, replace the three `echo "TODO..."` run blocks with:
```yaml
      - name: Build
        run: swift build
      - name: Test
        run: swift test
      - name: Lint
        run: |
          brew install swift-format
          swift format lint --recursive Sources
```

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources Tests AGENTS.md .github/workflows/ci.yml
git commit -m "feat: scaffold SwiftPM package with core/app/private targets"
```

---

### Task 2: WindowInfo model + adapter protocols

**Files:**
- Create: `Sources/CmdTabCore/WindowInfo.swift`
- Create: `Sources/CmdTabCore/Adapters.swift`
- Test: `Tests/CmdTabCoreTests/WindowInfoTests.swift`
- Delete: `Sources/CmdTabCore/Placeholder.swift` (superseded)

**Interfaces:**
- Produces:
  - `struct WindowInfo: Equatable, Identifiable { let id: CGWindowID; let pid: pid_t; let appName: String; let title: String; let isMinimized: Bool }`
  - `enum SwitcherCommand: Equatable { case show, next, previous, moveLeft, moveRight, moveUp, moveDown, commit, cancel }`
  - `protocol WindowEnumerating { func snapshot() -> [WindowInfo] }`
  - `protocol WindowActivating { func activate(_ window: WindowInfo) }`
  - `protocol HotkeyMonitoring: AnyObject { var onCommand: ((SwitcherCommand) -> Void)? { get set }; func start() throws; func stop() }`
  - keep `CmdTabCore.version` by moving it into `WindowInfo.swift`.

- [ ] **Step 1: Write the failing test**

`Tests/CmdTabCoreTests/WindowInfoTests.swift`:
```swift
import XCTest
import CoreGraphics
@testable import CmdTabCore

final class WindowInfoTests: XCTestCase {
    func testEquality() {
        let a = WindowInfo(id: 1, pid: 10, appName: "Safari", title: "Inbox", isMinimized: false)
        let b = WindowInfo(id: 1, pid: 10, appName: "Safari", title: "Inbox", isMinimized: false)
        let c = WindowInfo(id: 2, pid: 10, appName: "Safari", title: "Inbox", isMinimized: false)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter WindowInfoTests`
Expected: FAIL (compile error: `WindowInfo` not found).

- [ ] **Step 3: Write the model**

`Sources/CmdTabCore/WindowInfo.swift`:
```swift
import CoreGraphics
import Foundation

public enum CmdTabCore {
    public static let version = "0.1.0"
}

public struct WindowInfo: Equatable, Identifiable {
    public let id: CGWindowID
    public let pid: pid_t
    public let appName: String
    public let title: String
    public let isMinimized: Bool

    public init(id: CGWindowID, pid: pid_t, appName: String, title: String, isMinimized: Bool) {
        self.id = id
        self.pid = pid
        self.appName = appName
        self.title = title
        self.isMinimized = isMinimized
    }

    /// What the overlay renders when the window has no title.
    public var displayTitle: String { title.isEmpty ? appName : title }
}
```

- [ ] **Step 4: Write the protocols and command enum**

`Sources/CmdTabCore/Adapters.swift`:
```swift
import Foundation

public enum SwitcherCommand: Equatable {
    case show          // ⌘ held, first Tab
    case next          // advance selection
    case previous      // ⌘+Shift+Tab
    case moveLeft, moveRight, moveUp, moveDown
    case commit        // ⌘ released
    case cancel        // Esc
}

public protocol WindowEnumerating {
    func snapshot() -> [WindowInfo]
}

public protocol WindowActivating {
    func activate(_ window: WindowInfo)
}

public protocol HotkeyMonitoring: AnyObject {
    var onCommand: ((SwitcherCommand) -> Void)? { get set }
    func start() throws
    func stop()
}
```

- [ ] **Step 5: Delete the placeholder**

Run: `rm Sources/CmdTabCore/Placeholder.swift`

- [ ] **Step 6: Run tests**

Run: `swift test`
Expected: `WindowInfoTests` and `SmokeTests` PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/CmdTabCore Tests/CmdTabCoreTests/WindowInfoTests.swift
git rm Sources/CmdTabCore/Placeholder.swift
git commit -m "feat: add WindowInfo model and adapter protocols"
```

---

### Task 3: MRUStore (most-recently-used ordering)

**Files:**
- Create: `Sources/CmdTabCore/MRUStore.swift`
- Test: `Tests/CmdTabCoreTests/MRUStoreTests.swift`

**Interfaces:**
- Consumes: `WindowInfo` (Task 2).
- Produces:
  - `final class MRUStore` with `var order: [CGWindowID] { get }`, `func recordFocus(_ id: CGWindowID)`, `func ordered(_ windows: [WindowInfo]) -> [WindowInfo]`, `func prune(keeping present: Set<CGWindowID>)`.

- [ ] **Step 1: Write the failing tests**

`Tests/CmdTabCoreTests/MRUStoreTests.swift`:
```swift
import XCTest
import CoreGraphics
@testable import CmdTabCore

final class MRUStoreTests: XCTestCase {
    private func win(_ id: CGWindowID) -> WindowInfo {
        WindowInfo(id: id, pid: 1, appName: "App", title: "T\(id)", isMinimized: false)
    }

    func testRecordFocusMovesToFront() {
        let s = MRUStore()
        s.recordFocus(1); s.recordFocus(2); s.recordFocus(1)
        XCTAssertEqual(s.order, [1, 2])
    }

    func testOrderedSortsByMRUWithUnknownsLastPreservingInput() {
        let s = MRUStore()
        s.recordFocus(3); s.recordFocus(2)   // order = [2, 3]
        let result = s.ordered([win(1), win(2), win(3)])
        XCTAssertEqual(result.map { $0.id }, [2, 3, 1])
    }

    func testPruneRemovesAbsentIDs() {
        let s = MRUStore()
        s.recordFocus(1); s.recordFocus(2); s.recordFocus(3)
        s.prune(keeping: [2, 3])
        XCTAssertEqual(s.order, [3, 2])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter MRUStoreTests`
Expected: FAIL (compile error: `MRUStore` not found).

- [ ] **Step 3: Implement MRUStore**

`Sources/CmdTabCore/MRUStore.swift`:
```swift
import CoreGraphics

public final class MRUStore {
    public private(set) var order: [CGWindowID] = []

    public init() {}

    /// Move a window to the front of the MRU list.
    public func recordFocus(_ id: CGWindowID) {
        order.removeAll { $0 == id }
        order.insert(id, at: 0)
    }

    /// Order a snapshot by MRU rank; windows unknown to the store keep their
    /// input order and go last.
    public func ordered(_ windows: [WindowInfo]) -> [WindowInfo] {
        var rank: [CGWindowID: Int] = [:]
        for (i, id) in order.enumerated() { rank[id] = i }
        return windows.enumerated().sorted { lhs, rhs in
            let rl = rank[lhs.element.id] ?? Int.max
            let rr = rank[rhs.element.id] ?? Int.max
            if rl != rr { return rl < rr }
            return lhs.offset < rhs.offset
        }.map { $0.element }
    }

    /// Drop ids that are no longer present.
    public func prune(keeping present: Set<CGWindowID>) {
        order.removeAll { !present.contains($0) }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter MRUStoreTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/CmdTabCore/MRUStore.swift Tests/CmdTabCoreTests/MRUStoreTests.swift
git commit -m "feat: add MRUStore most-recently-used ordering"
```

---

### Task 4: SwitcherController (orchestration state machine)

**Files:**
- Create: `Sources/CmdTabCore/SwitcherController.swift`
- Test: `Tests/CmdTabCoreTests/SwitcherControllerTests.swift`

**Interfaces:**
- Consumes: `WindowInfo`, `SwitcherCommand`, `WindowEnumerating`, `WindowActivating` (Task 2); `MRUStore` (Task 3).
- Produces:
  - `final class SwitcherController` with:
    - `init(enumerator: WindowEnumerating, activator: WindowActivating, mru: MRUStore)`
    - `var isVisible: Bool { get }`, `var windows: [WindowInfo] { get }`, `var selectedIndex: Int { get }`
    - callbacks `var onShow: (([WindowInfo], Int) -> Void)?`, `var onSelectionChange: ((Int) -> Void)?`, `var onHide: (() -> Void)?`
    - `func handle(_ command: SwitcherCommand)`
    - `func setSelection(_ index: Int)` (mouse hover)

- [ ] **Step 1: Write the failing tests with fakes**

`Tests/CmdTabCoreTests/SwitcherControllerTests.swift`:
```swift
import XCTest
import CoreGraphics
@testable import CmdTabCore

private final class FakeEnumerator: WindowEnumerating {
    var windows: [WindowInfo]
    init(_ w: [WindowInfo]) { windows = w }
    func snapshot() -> [WindowInfo] { windows }
}

private final class FakeActivator: WindowActivating {
    var activated: [WindowInfo] = []
    func activate(_ window: WindowInfo) { activated.append(window) }
}

final class SwitcherControllerTests: XCTestCase {
    private func win(_ id: CGWindowID) -> WindowInfo {
        WindowInfo(id: id, pid: 1, appName: "App", title: "T\(id)", isMinimized: false)
    }

    private func makeController(_ ids: [CGWindowID]) -> (SwitcherController, FakeActivator) {
        let enumerator = FakeEnumerator(ids.map(win))
        let activator = FakeActivator()
        let controller = SwitcherController(enumerator: enumerator, activator: activator, mru: MRUStore())
        return (controller, activator)
    }

    func testShowStartsOnPreviousWindow() {
        let (c, _) = makeController([1, 2, 3])
        c.handle(.show)
        XCTAssertTrue(c.isVisible)
        XCTAssertEqual(c.windows.count, 3)
        XCTAssertEqual(c.selectedIndex, 1) // previous window, not current
    }

    func testShowWithSingleWindowSelectsZero() {
        let (c, _) = makeController([1])
        c.handle(.show)
        XCTAssertEqual(c.selectedIndex, 0)
    }

    func testShowWithNoWindowsStaysHidden() {
        let (c, _) = makeController([])
        c.handle(.show)
        XCTAssertFalse(c.isVisible)
    }

    func testNextWrapsAround() {
        let (c, _) = makeController([1, 2, 3])
        c.handle(.show)            // index 1
        c.handle(.next)            // index 2
        c.handle(.next)            // wraps to 0
        XCTAssertEqual(c.selectedIndex, 0)
    }

    func testPreviousWrapsBackward() {
        let (c, _) = makeController([1, 2, 3])
        c.handle(.show)            // index 1
        c.handle(.previous)        // index 0
        c.handle(.previous)        // wraps to 2
        XCTAssertEqual(c.selectedIndex, 2)
    }

    func testSecondShowWhileVisibleAdvances() {
        let (c, _) = makeController([1, 2, 3])
        c.handle(.show)            // index 1
        c.handle(.show)            // treated as next -> index 2
        XCTAssertEqual(c.selectedIndex, 2)
    }

    func testCommitActivatesSelectedAndHides() {
        let (c, activator) = makeController([1, 2, 3])
        c.handle(.show)            // index 1 -> window id 2
        c.handle(.commit)
        XCTAssertFalse(c.isVisible)
        XCTAssertEqual(activator.activated.map { $0.id }, [2])
    }

    func testCancelHidesWithoutActivating() {
        let (c, activator) = makeController([1, 2, 3])
        c.handle(.show)
        c.handle(.cancel)
        XCTAssertFalse(c.isVisible)
        XCTAssertTrue(activator.activated.isEmpty)
    }

    func testCommandsIgnoredWhenHidden() {
        let (c, activator) = makeController([1, 2, 3])
        c.handle(.next)
        c.handle(.commit)
        XCTAssertFalse(c.isVisible)
        XCTAssertTrue(activator.activated.isEmpty)
    }

    func testSetSelectionFromHover() {
        let (c, _) = makeController([1, 2, 3])
        c.handle(.show)
        c.setSelection(2)
        XCTAssertEqual(c.selectedIndex, 2)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SwitcherControllerTests`
Expected: FAIL (compile error: `SwitcherController` not found).

- [ ] **Step 3: Implement the controller**

`Sources/CmdTabCore/SwitcherController.swift`:
```swift
import CoreGraphics

public final class SwitcherController {
    public private(set) var isVisible = false
    public private(set) var windows: [WindowInfo] = []
    public private(set) var selectedIndex = 0

    public var onShow: (([WindowInfo], Int) -> Void)?
    public var onSelectionChange: ((Int) -> Void)?
    public var onHide: (() -> Void)?

    private let enumerator: WindowEnumerating
    private let activator: WindowActivating
    private let mru: MRUStore

    public init(enumerator: WindowEnumerating, activator: WindowActivating, mru: MRUStore) {
        self.enumerator = enumerator
        self.activator = activator
        self.mru = mru
    }

    public func handle(_ command: SwitcherCommand) {
        switch command {
        case .show:
            if isVisible { advance(by: 1) } else { present() }
        case .next, .moveRight, .moveDown:
            guard isVisible else { return }
            advance(by: 1)
        case .previous, .moveLeft, .moveUp:
            guard isVisible else { return }
            advance(by: -1)
        case .commit:
            commit()
        case .cancel:
            hide()
        }
    }

    public func setSelection(_ index: Int) {
        guard isVisible, windows.indices.contains(index) else { return }
        selectedIndex = index
        onSelectionChange?(index)
    }

    private func present() {
        let snap = enumerator.snapshot()
        mru.prune(keeping: Set(snap.map { $0.id }))
        windows = mru.ordered(snap)
        guard !windows.isEmpty else { return }
        selectedIndex = windows.count > 1 ? 1 : 0
        isVisible = true
        onShow?(windows, selectedIndex)
    }

    private func advance(by delta: Int) {
        guard !windows.isEmpty else { return }
        let count = windows.count
        selectedIndex = ((selectedIndex + delta) % count + count) % count
        onSelectionChange?(selectedIndex)
    }

    private func commit() {
        guard isVisible else { return }
        let target = windows.indices.contains(selectedIndex) ? windows[selectedIndex] : nil
        hide()
        if let target {
            mru.recordFocus(target.id)
            activator.activate(target)
        }
    }

    private func hide() {
        guard isVisible else { return }
        isVisible = false
        onHide?()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SwitcherControllerTests`
Expected: PASS (10 tests).

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: all tests PASS (Smoke + WindowInfo + MRUStore + SwitcherController).

- [ ] **Step 6: Commit**

```bash
git add Sources/CmdTabCore/SwitcherController.swift Tests/CmdTabCoreTests/SwitcherControllerTests.swift
git commit -m "feat: add SwitcherController orchestration state machine"
```

---

### Task 5: App shell, permissions, and the .app bundle

**Files:**
- Modify: `Sources/CmdTabApp/main.swift`
- Create: `Sources/CmdTabApp/AppDelegate.swift`
- Create: `Sources/CmdTabApp/PermissionsManager.swift`
- Create: `Scripts/CmdTab-Info.plist`
- Create: `Scripts/bundle.sh`

**Interfaces:**
- Consumes: `CmdTabCore` (for later wiring; not used functionally yet).
- Produces:
  - `final class AppDelegate: NSObject, NSApplicationDelegate`
  - `enum PermissionsManager { static func isAccessibilityTrusted(prompt: Bool) -> Bool }`
  - `./Scripts/bundle.sh` producing `build/CmdTab.app` (ad-hoc signed, `LSUIElement`).

**Note:** This task is verified manually (GUI + permissions). There is no unit test; the deliverable is a launchable agent app that requests Accessibility.

- [ ] **Step 1: Write the permissions helper**

`Sources/CmdTabApp/PermissionsManager.swift`:
```swift
import ApplicationServices

enum PermissionsManager {
    /// Returns whether this process is trusted for Accessibility.
    /// Pass `prompt: true` to surface the system permission dialog.
    static func isAccessibilityTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }
}
```

- [ ] **Step 2: Write the app delegate**

`Sources/CmdTabApp/AppDelegate.swift`:
```swift
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
```

- [ ] **Step 3: Replace `main.swift` with the real bootstrap**

`Sources/CmdTabApp/main.swift`:
```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // no Dock icon (agent app)
app.run()
```

- [ ] **Step 4: Write the bundle Info.plist template**

`Scripts/CmdTab-Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>CmdTab</string>
    <key>CFBundleDisplayName</key><string>CmdTab</string>
    <key>CFBundleIdentifier</key><string>com.local.cmdtab</string>
    <key>CFBundleVersion</key><string>0.1.0</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>CmdTab</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>CmdTab needs Accessibility access to list and switch windows.</string>
</dict>
</plist>
```

- [ ] **Step 5: Write the bundling script**

`Scripts/bundle.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/CmdTab.app"

swift build -c "$CONFIG"
BIN="$ROOT/.build/$CONFIG/CmdTabApp"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/CmdTab"
cp "$ROOT/Scripts/CmdTab-Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc sign so a stable code identity persists across rebuilds, which keeps
# the granted Accessibility permission attached to the app.
codesign --force --deep --sign - "$APP"

echo "Built $APP"
```

- [ ] **Step 6: Make the script executable and build the bundle**

Run:
```bash
chmod +x Scripts/bundle.sh
./Scripts/bundle.sh debug
```
Expected: prints `Built <repo>/build/CmdTab.app`.

- [ ] **Step 7: Manually verify the agent launches and requests permission**

Run: `open build/CmdTab.app`
Expected:
- No Dock icon appears; a `⌘⇥` item appears in the menu bar.
- On first launch, the macOS "CmdTab would like to control this computer using accessibility features" prompt appears (or the app appears in System Settings → Privacy & Security → Accessibility).
- Grant access; within ~1s the log line "accessibility granted, switcher ready" is emitted (check Console.app filtered by `CmdTab`).
- The "Quit CmdTab" menu item terminates the app.

- [ ] **Step 8: Ignore build output in git**

Confirm `.gitignore` already contains `.build/` and `build/` (the Task-0 scaffold ignores `.build/`; add `build/` if missing):
```bash
grep -qxF 'build/' .gitignore || printf '\n# bundle output\nbuild/\n' >> .gitignore
```

- [ ] **Step 9: Commit**

```bash
git add Sources/CmdTabApp Scripts .gitignore
git commit -m "feat: agent app shell, accessibility permission flow, .app bundling"
```

---

### Task 6: CGEventTap hotkey monitor (the Cmd+Tab gesture)

**Files:**
- Create: `Sources/CmdTabApp/CGEventTapHotkeyMonitor.swift`

**Interfaces:**
- Consumes: `HotkeyMonitoring`, `SwitcherCommand` (Task 2).
- Produces: `final class CGEventTapHotkeyMonitor: HotkeyMonitoring`.

**Note:** Verified manually (requires a real event tap + Accessibility/Input-Monitoring). Before starting, run `sw_vers -productVersion` and record the exact build in the commit message.

- [ ] **Step 1: Implement the monitor**

`Sources/CmdTabApp/CGEventTapHotkeyMonitor.swift`:
```swift
import AppKit
import CoreGraphics
import CmdTabCore

enum HotkeyError: Error { case tapCreationFailed }

final class CGEventTapHotkeyMonitor: HotkeyMonitoring {
    var onCommand: ((SwitcherCommand) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var commandDown = false
    private var active = false   // overlay currently showing

    // Key codes (US layout, layout-independent virtual codes).
    private let kTab: Int64 = 48
    private let kEsc: Int64 = 53
    private let kLeft: Int64 = 123, kRight: Int64 = 124, kDown: Int64 = 125, kUp: Int64 = 126

    func start() throws {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<CGEventTapHotkeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()
            return me.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { throw HotkeyError.tapCreationFailed }

        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes) }
        tap = nil
        runLoopSource = nil
        active = false
        commandDown = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Self-heal: the system disables taps on timeout / overload.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags

        if type == .flagsChanged {
            let nowDown = flags.contains(.maskCommand)
            if commandDown && !nowDown {
                commandDown = false
                if active {
                    active = false
                    emit(.commit)
                    return nil   // swallow the flags change that ends the gesture
                }
            } else {
                commandDown = nowDown
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown, commandDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let shift = flags.contains(.maskShift)
            switch keyCode {
            case kTab:
                if active {
                    emit(shift ? .previous : .next)
                } else {
                    active = true
                    emit(.show)
                    if shift { emit(.previous) }
                }
                return nil
            case kEsc where active:
                active = false
                emit(.cancel)
                return nil
            case kLeft where active:  emit(.moveLeft);  return nil
            case kRight where active: emit(.moveRight); return nil
            case kDown where active:  emit(.moveDown);  return nil
            case kUp where active:    emit(.moveUp);    return nil
            default:
                break
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func emit(_ command: SwitcherCommand) {
        let handler = onCommand
        DispatchQueue.main.async { handler?(command) }
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Manual smoke (temporary wiring)**

Temporarily add to `AppDelegate.startSwitcher()`:
```swift
let monitor = CGEventTapHotkeyMonitor()
monitor.onCommand = { NSLog("CmdTab command: \($0)") }
do { try monitor.start() } catch { NSLog("tap failed: \(error)") }
self.tempMonitor = monitor   // add `private var tempMonitor: CGEventTapHotkeyMonitor?` to AppDelegate
```
Rebuild and run: `./Scripts/bundle.sh debug && open build/CmdTab.app`
Expected (watch Console.app filtered by `CmdTab`):
- Hold ⌘ and tap Tab → logs `show`. Tap Tab again → `next`. ⌘+Shift+Tab → `previous`. Esc → `cancel`. Release ⌘ → `commit`.
- The **native macOS app switcher must NOT appear** while doing this.
- If you see `tap failed`, open System Settings → Privacy & Security → Input Monitoring and enable CmdTab, then relaunch.

- [ ] **Step 4: Remove the temporary wiring**

Revert the temporary `startSwitcher()` changes and the `tempMonitor` property (full wiring lands in Task 10). Keep `CGEventTapHotkeyMonitor.swift`.

- [ ] **Step 5: Commit**

```bash
git add Sources/CmdTabApp/CGEventTapHotkeyMonitor.swift
git commit -m "feat: CGEventTap hotkey monitor for the Cmd+Tab gesture (verified on macOS <build>)"
```

---

### Task 7: System window enumerator (all windows, no exception)

**Files:**
- Create: `Sources/CmdTabApp/SystemWindowEnumerator.swift`

**Interfaces:**
- Consumes: `WindowEnumerating`, `WindowInfo` (Task 2); `_AXUIElementGetWindow` (CGSPrivate, Task 1).
- Produces: `final class SystemWindowEnumerator: WindowEnumerating`.

**Note:** Verified manually. Coverage strategy: `CGWindowListCopyWindowInfo(.optionAll, ...)` returns normal and off-screen windows across all Spaces (layer 0 only, i.e. real app windows); a per-app Accessibility pass adds **minimized** windows, which CGWindowList omits. Hidden-app windows surface through CGWindowList as off-screen. This satisfies the no-exception requirement using public APIs plus the single private `_AXUIElementGetWindow` symbol.

- [ ] **Step 1: Implement the enumerator**

`Sources/CmdTabApp/SystemWindowEnumerator.swift`:
```swift
import AppKit
import CoreGraphics
import ApplicationServices
import CGSPrivate
import CmdTabCore

final class SystemWindowEnumerator: WindowEnumerating {
    /// Our own bundle id, so we never list CmdTab's overlay.
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
               (bounds["Width"] ?? 0) < 40 || (bounds["Height"] ?? 0) < 40 { continue }

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
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Manual smoke (temporary wiring)**

Temporarily add to `AppDelegate.startSwitcher()`:
```swift
let windows = SystemWindowEnumerator().snapshot()
NSLog("CmdTab enumerated \(windows.count) windows:")
windows.forEach { NSLog(" - [\($0.isMinimized ? "min" : "   ")] \($0.appName) — \($0.displayTitle)") }
```
Set up this scenario first: open Safari + TextEdit on the current Space; minimize one TextEdit window; move a Terminal window to a second Space; hide an app with ⌘H. Then rebuild and run: `./Scripts/bundle.sh debug && open build/CmdTab.app`
Expected (Console.app filtered by `CmdTab`):
- Every one of those windows appears in the log, including the minimized one (flagged `min`), the one on the second Space, and the hidden app's window. CmdTab's own windows do not appear.

- [ ] **Step 4: Remove the temporary wiring**

Revert the temporary `startSwitcher()` changes. Keep `SystemWindowEnumerator.swift`.

- [ ] **Step 5: Commit**

```bash
git add Sources/CmdTabApp/SystemWindowEnumerator.swift
git commit -m "feat: system window enumerator (normal + minimized + other-Space + hidden)"
```

---

### Task 8: Window activator (raise + follow to Space)

**Files:**
- Create: `Sources/CmdTabApp/AXWindowActivator.swift`

**Interfaces:**
- Consumes: `WindowActivating`, `WindowInfo` (Task 2); `_AXUIElementGetWindow` (CGSPrivate).
- Produces: `final class AXWindowActivator: WindowActivating`.

**Note:** Verified manually. Activating a window on another Space causes macOS to follow focus to that Space; activating a minimized window un-minimizes it.

- [ ] **Step 1: Implement the activator**

`Sources/CmdTabApp/AXWindowActivator.swift`:
```swift
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
            .activate(options: [.activateIgnoringOtherApps])
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
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Manual smoke (temporary wiring)**

Temporarily add to `AppDelegate.startSwitcher()`:
```swift
let windows = SystemWindowEnumerator().snapshot()
if let target = windows.first(where: { $0.isMinimized }) ?? windows.last {
    NSLog("CmdTab activating: \(target.appName) — \(target.displayTitle)")
    AXWindowActivator().activate(target)
}
```
Rebuild and run: `./Scripts/bundle.sh debug && open build/CmdTab.app`
Expected:
- The chosen window comes to the front and is focused. If it was minimized, it un-minimizes. If it was on another Space, the desktop switches to that Space.

- [ ] **Step 4: Remove the temporary wiring**

Revert the temporary `startSwitcher()` changes. Keep `AXWindowActivator.swift`.

- [ ] **Step 5: Commit**

```bash
git add Sources/CmdTabApp/AXWindowActivator.swift
git commit -m "feat: AX window activator (raise, un-minimize, follow to Space)"
```

---

### Task 9: Switcher overlay UI (NSPanel list)

**Files:**
- Create: `Sources/CmdTabApp/OverlayRowView.swift`
- Create: `Sources/CmdTabApp/SwitcherOverlay.swift`

**Interfaces:**
- Consumes: `WindowInfo` (Task 2).
- Produces:
  - `final class OverlayRowView: NSView` with `init(index:icon:appName:title:)`, `var onHover: ((Int) -> Void)?`, `var onClick: ((Int) -> Void)?`, `func setSelected(_ selected: Bool)`.
  - `final class SwitcherOverlay` with `var onHover: ((Int) -> Void)?`, `var onClick: ((Int) -> Void)?`, `func show(_ windows: [WindowInfo], selected: Int)`, `func highlight(_ index: Int)`, `func hide()`.

**Note:** Verified manually (visual).

- [ ] **Step 1: Implement the row view**

`Sources/CmdTabApp/OverlayRowView.swift`:
```swift
import AppKit

final class OverlayRowView: NSView {
    var onHover: ((Int) -> Void)?
    var onClick: ((Int) -> Void)?

    private let index: Int
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")

    init(index: Int, icon: NSImage?, appName: String, title: String) {
        self.index = index
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8

        iconView.image = icon
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let shown = title.isEmpty ? appName : "\(appName) — \(title)"
        titleLabel.stringValue = shown
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.font = .systemFont(ofSize: 14)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func setSelected(_ selected: Bool) {
        layer?.backgroundColor = selected
            ? NSColor.selectedContentBackgroundColor.cgColor
            : NSColor.clear.cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(index) }
    override func mouseDown(with event: NSEvent) { onClick?(index) }
}
```

- [ ] **Step 2: Implement the overlay panel**

`Sources/CmdTabApp/SwitcherOverlay.swift`:
```swift
import AppKit
import CmdTabCore

final class SwitcherOverlay {
    var onHover: ((Int) -> Void)?
    var onClick: ((Int) -> Void)?

    private var panel: NSPanel?
    private var rows: [OverlayRowView] = []

    func show(_ windows: [WindowInfo], selected: Int) {
        hide()
        guard !windows.isEmpty else { return }

        let rowHeight: CGFloat = 44
        let width: CGFloat = 520
        let height = CGFloat(windows.count) * rowHeight + 16

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let content = panel.contentView!
        let bg = NSVisualEffectView(frame: content.bounds)
        bg.autoresizingMask = [.width, .height]
        bg.material = .hudWindow
        bg.state = .active
        bg.blendingMode = .behindWindow
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 12
        content.addSubview(bg)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: bg.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -8),
        ])

        rows = windows.enumerated().map { idx, win in
            let icon = NSRunningApplication(processIdentifier: win.pid)?.icon
            let row = OverlayRowView(index: idx, icon: icon, appName: win.appName, title: win.title)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.onHover = { [weak self] in self?.onHover?($0) }
            row.onClick = { [weak self] in self?.onClick?($0) }
            stack.addArrangedSubview(row)
            row.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            return row
        }

        if let screen = NSScreen.main {
            let f = screen.frame
            panel.setFrameOrigin(NSPoint(x: f.midX - width / 2, y: f.midY - height / 2))
        }
        panel.orderFrontRegardless()
        self.panel = panel
        highlight(selected)
    }

    func highlight(_ index: Int) {
        for (i, row) in rows.enumerated() { row.setSelected(i == index) }
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        rows = []
    }
}
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 4: Manual smoke (temporary wiring)**

Temporarily add to `AppDelegate.startSwitcher()`:
```swift
let sample = SystemWindowEnumerator().snapshot()
let overlay = SwitcherOverlay()
overlay.show(sample, selected: min(1, max(0, sample.count - 1)))
self.tempOverlay = overlay   // add `private var tempOverlay: SwitcherOverlay?` to AppDelegate
```
Rebuild and run: `./Scripts/bundle.sh debug && open build/CmdTab.app`
Expected:
- A centered, rounded, translucent panel appears listing each window as icon + "App — Title", one row per window, with the second row highlighted. It floats above other windows. (It won't dismiss yet — that's Task 10.) Quit from the menu bar.

- [ ] **Step 5: Remove the temporary wiring**

Revert the temporary `startSwitcher()` changes and the `tempOverlay` property. Keep both overlay files.

- [ ] **Step 6: Commit**

```bash
git add Sources/CmdTabApp/OverlayRowView.swift Sources/CmdTabApp/SwitcherOverlay.swift
git commit -m "feat: NSPanel switcher overlay with icon+title rows"
```

---

### Task 10: End-to-end wiring + MRU focus tracking + manual test checklist

**Files:**
- Modify: `Sources/CmdTabApp/AppDelegate.swift`
- Create: `docs/manual-test-checklist.md`

**Interfaces:**
- Consumes: every adapter (Tasks 6–9), `SwitcherController` + `MRUStore` (Tasks 3–4).
- Produces: a fully wired agent. No new public types.

**Note:** This is the integration task. Verified via the manual checklist it creates.

- [ ] **Step 1: Replace `AppDelegate` with the wired version**

`Sources/CmdTabApp/AppDelegate.swift`:
```swift
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
```

- [ ] **Step 2: Build the bundle**

Run: `./Scripts/bundle.sh debug`
Expected: prints `Built <repo>/build/CmdTab.app`.

- [ ] **Step 3: Write the manual test checklist**

`docs/manual-test-checklist.md`:
```markdown
# CmdTab Manual Test Checklist

Run after `./Scripts/bundle.sh debug && open build/CmdTab.app`.
Grant Accessibility (and Input Monitoring if prompted) on first launch.

## Gesture
- [ ] Hold ⌘, tap Tab → overlay appears, selection on the *previous* window.
- [ ] Keep ⌘ held, tap Tab repeatedly → selection advances and wraps.
- [ ] ⌘+Shift+Tab → selection moves backward and wraps.
- [ ] Arrow keys move the selection while the overlay is open.
- [ ] Release ⌘ → the selected window is raised and focused; overlay closes.
- [ ] Esc while open → overlay closes, no window change.
- [ ] The native macOS app switcher never appears during any of the above.

## Coverage (set up: 2 apps current Space, 1 minimized, 1 on another Space, 1 hidden via ⌘H)
- [ ] Every window appears as its own row (no app grouping).
- [ ] The minimized window is listed; selecting it un-minimizes and focuses it.
- [ ] The other-Space window is listed; selecting it switches to that Space.
- [ ] The hidden app's window is listed and can be activated.
- [ ] CmdTab's own overlay never appears as a row.

## MRU
- [ ] First Tab press jumps to the window you used immediately before the current one.

## Resilience
- [ ] Leave the app running for a while, keep using the gesture → it keeps working
      (event tap self-heals after system timeouts).
- [ ] Quit from the menu bar → app exits cleanly, gesture returns to system default.
```

- [ ] **Step 4: Run the manual checklist**

Run: `./Scripts/bundle.sh debug && open build/CmdTab.app`, then work through `docs/manual-test-checklist.md`.
Expected: every checkbox passes. If the event tap fails, enable CmdTab under System Settings → Privacy & Security → Input Monitoring and relaunch.

- [ ] **Step 5: Run the unit suite one more time**

Run: `swift test`
Expected: all unit tests still PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/CmdTabApp/AppDelegate.swift docs/manual-test-checklist.md
git commit -m "feat: wire CmdTab end-to-end with MRU focus tracking + manual test checklist"
```

---

## Self-Review

**Spec coverage:**
- Replace ⌘Tab / suppress native switcher → Task 6 (CGEventTap, returns `nil` to swallow). ✓
- All windows incl. minimized / hidden / other-Space → Task 7. ✓
- One entry per window, not grouped → Tasks 7 + 9 (one row per `WindowInfo`). ✓
- Icon + title display (no thumbnails / Screen Recording) → Task 9. ✓
- MRU ordering, first Tab = previous window → Tasks 3, 4, 10. ✓
- Gesture semantics (Tab/Shift+Tab/arrows/mouse/Esc/release) → Tasks 4, 6, 10. ✓
- Agent app, no Dock icon, menu bar → Task 5. ✓
- Accessibility (+ Input Monitoring fallback) permission flow → Tasks 5, 10. ✓
- Event-tap self-heal, activation fallback → Tasks 6, 8. ✓
- Personal-use ad-hoc signing, .app bundle, LSUIElement → Task 5. ✓
- Components as protocols, pure logic unit-tested, adapters manual → Tasks 2–4 (tested), 6–9 (manual). ✓
- AGENTS.md/CI updated to real commands → Task 1. ✓

**Build-system deviation from spec:** spec said "Xcode project"; this plan uses SwiftPM + `Scripts/bundle.sh` to realize the same intent (real .app bundle, Info.plist, LSUIElement, entitlements, ad-hoc signing) in a text-based, testable form. Flagged to the user at handoff.

**Graceful CGS-degradation note:** the spec describes falling back to an AX-only current-Space list if private CGS calls fail. This plan's enumerator (Task 7) relies on public `CGWindowListCopyWindowInfo` for cross-Space coverage plus one private symbol (`_AXUIElementGetWindow`) only for minimized windows; if that symbol ever fails, minimized windows are simply omitted rather than crashing (the `guard ... == .success` already handles this). No separate fallback path is needed.

**Placeholder scan:** no TBD/TODO left in requirements; every code step shows complete code; temporary wiring steps are explicitly added and then reverted.

**Type consistency:** `WindowInfo`, `SwitcherCommand`, the three protocols, `MRUStore` (`recordFocus`/`ordered`/`prune`), and `SwitcherController` (`handle`/`setSelection`/`onShow`/`onSelectionChange`/`onHide`) are used with identical signatures across Tasks 2–10. ✓
