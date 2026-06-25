# Reserved window-state icon zone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give each overlay row a fixed-width right-hand zone showing up to three window-state icons, expanding the state set from three to six (adds on-another-Space, dialog, current window).

**Architecture:** `WindowInfo` (in `CmdTabCore`) gains three boolean fields. `OverlayRowView` renders a fixed-width reserved zone with all six possible icons in a stable priority order, right-aligned. `SystemWindowEnumerator` populates dialog/current from AX and on-another-Space from the private CGS Spaces API (declared in the `CGSPrivate` C module). CGS work is sequenced last so it can be dropped without unwinding the rest.

**Tech Stack:** Swift, AppKit, ApplicationServices (Accessibility), private CoreGraphics/SkyLight (CGS), XCTest.

## Global Constraints

- Swift, targeting macOS. Follow the Swift API Design Guidelines.
- New `WindowInfo` initializer parameters must have `= false` defaults so existing test helpers compile unchanged.
- Icons appear only when their state is true — no placeholder/greyed icons. All icons tinted `.secondaryLabelColor`, sized 16×16.
- The reserved icon zone is a fixed width of **3 slots** = `3 * 16 + 2 * 6 = 60` pt, always present, icons right-aligned within it.
- Fixed icon priority order, left → right: `current, dialog, minimized, fullScreen, onOtherSpace, hidden`.
- SF Symbols: current → `checkmark.circle`, dialog → `exclamationmark.bubble`, minimized → `minus.circle`, full screen → `arrow.up.left.and.arrow.down.right`, on-another-Space → `macwindow.on.rectangle`, hidden → `eye.slash`.
- Suppression: on-another-Space is reported only when the window is neither minimized nor full screen.

---

### Task 1: Extend `WindowInfo` model

**Files:**
- Modify: `Sources/CmdTabCore/WindowInfo.swift`
- Test: `Tests/CmdTabCoreTests/WindowInfoTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `WindowInfo` stored properties `isOnOtherSpace: Bool`, `isDialog: Bool`, `isCurrent: Bool`; initializer extended with `isOnOtherSpace: Bool = false, isDialog: Bool = false, isCurrent: Bool = false` (after the existing `isHidden`).

- [ ] **Step 1: Write the failing test**

Add this test method to `Tests/CmdTabCoreTests/WindowInfoTests.swift` (inside the existing `WindowInfoTests` class):

```swift
    func testNewStateFlagsDefaultFalseAndStore() {
        let plain = WindowInfo(id: 1, pid: 10, appName: "Safari", title: "Inbox", isMinimized: false)
        XCTAssertFalse(plain.isOnOtherSpace)
        XCTAssertFalse(plain.isDialog)
        XCTAssertFalse(plain.isCurrent)

        let flagged = WindowInfo(
            id: 2, pid: 10, appName: "Safari", title: "Inbox",
            isMinimized: false, isFullScreen: false, isHidden: false,
            isOnOtherSpace: true, isDialog: true, isCurrent: true
        )
        XCTAssertTrue(flagged.isOnOtherSpace)
        XCTAssertTrue(flagged.isDialog)
        XCTAssertTrue(flagged.isCurrent)
        XCTAssertNotEqual(plain, flagged)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter WindowInfoTests`
Expected: FAIL — compile error, `WindowInfo` has no member `isOnOtherSpace`.

- [ ] **Step 3: Write minimal implementation**

Replace the struct in `Sources/CmdTabCore/WindowInfo.swift` with:

```swift
public struct WindowInfo: Equatable, Identifiable {
    public let id: CGWindowID
    public let pid: pid_t
    public let appName: String
    public let title: String
    public let isMinimized: Bool
    public let isFullScreen: Bool
    public let isHidden: Bool
    public let isOnOtherSpace: Bool
    public let isDialog: Bool
    public let isCurrent: Bool

    public init(
        id: CGWindowID,
        pid: pid_t,
        appName: String,
        title: String,
        isMinimized: Bool,
        isFullScreen: Bool = false,
        isHidden: Bool = false,
        isOnOtherSpace: Bool = false,
        isDialog: Bool = false,
        isCurrent: Bool = false
    ) {
        self.id = id
        self.pid = pid
        self.appName = appName
        self.title = title
        self.isMinimized = isMinimized
        self.isFullScreen = isFullScreen
        self.isHidden = isHidden
        self.isOnOtherSpace = isOnOtherSpace
        self.isDialog = isDialog
        self.isCurrent = isCurrent
    }

    /// What the overlay renders when the window has no title.
    public var displayTitle: String { title.isEmpty ? appName : title }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CmdTabCoreTests`
Expected: PASS — all CmdTabCore tests green.

- [ ] **Step 5: Commit**

```bash
git add Sources/CmdTabCore/WindowInfo.swift Tests/CmdTabCoreTests/WindowInfoTests.swift
git commit -m "feat: add isOnOtherSpace/isDialog/isCurrent to WindowInfo"
```

---

### Task 2: Fixed-width icon zone + wiring

**Files:**
- Modify: `Sources/CmdTabApp/OverlayRowView.swift`
- Modify: `Sources/CmdTabApp/SwitcherOverlay.swift`

**Interfaces:**
- Consumes: `WindowInfo.isOnOtherSpace`/`isDialog`/`isCurrent` (Task 1).
- Produces: `OverlayRowView.init(index:icon:appName:title:isMinimized:isFullScreen:isHidden:isOnOtherSpace:isDialog:isCurrent:)`.

> These two files share one compile cycle: changing `OverlayRowView`'s initializer breaks the `SwitcherOverlay` call site. Do both edits, build once, commit once. AppKit layout has no unit harness; verification is `swift build` + the manual pass in Task 5.

- [ ] **Step 1: Rewrite the `OverlayRowView` initializer**

In `Sources/CmdTabApp/OverlayRowView.swift`, replace the entire `init(...)` (the current `init` spanning the parameter list through the closing `}` of `NSLayoutConstraint.activate([...])`) with:

```swift
    init(
        index: Int,
        icon: NSImage?,
        appName: String,
        title: String,
        isMinimized: Bool,
        isFullScreen: Bool,
        isHidden: Bool,
        isOnOtherSpace: Bool,
        isDialog: Bool,
        isCurrent: Bool
    ) {
        self.index = index
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8

        iconView.image = icon
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let shown = title.isEmpty ? appName : "\(appName) — \(title)"
        titleLabel.stringValue = shown
        titleLabel.lineBreakMode = .byTruncatingTail
        // Yield rather than force the row (and panel) wider for long titles.
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.font = .systemFont(ofSize: 16)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Fixed-width reserved zone (3 icon slots), so every row's title
        // truncates at the same column. Active icons render right-aligned
        // inside it, in a stable priority order.
        let zoneWidth: CGFloat = 3 * 16 + 2 * 6   // 3 slots + inter-icon spacing
        let zone = NSView()
        zone.translatesAutoresizingMaskIntoConstraints = false

        let icons = NSStackView()
        icons.orientation = .horizontal
        icons.spacing = 6
        icons.translatesAutoresizingMaskIntoConstraints = false

        let symbols: [(Bool, String, String)] = [
            (isCurrent, "checkmark.circle", "Current window"),
            (isDialog, "exclamationmark.bubble", "Dialog"),
            (isMinimized, "minus.circle", "Minimized"),
            (isFullScreen, "arrow.up.left.and.arrow.down.right", "Full screen"),
            (isOnOtherSpace, "macwindow.on.rectangle", "On another Space"),
            (isHidden, "eye.slash", "Hidden"),
        ]
        for (active, symbol, label) in symbols where active {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            let view = NSImageView(image: image ?? NSImage())
            view.contentTintColor = .secondaryLabelColor
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalToConstant: 16).isActive = true
            view.heightAnchor.constraint(equalToConstant: 16).isActive = true
            icons.addArrangedSubview(view)
        }
        zone.addSubview(icons)

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(zone)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: zone.leadingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            zone.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            zone.centerYAnchor.constraint(equalTo: centerYAnchor),
            zone.widthAnchor.constraint(equalToConstant: zoneWidth),
            zone.heightAnchor.constraint(equalToConstant: 44),
            icons.trailingAnchor.constraint(equalTo: zone.trailingAnchor),
            icons.centerYAnchor.constraint(equalTo: zone.centerYAnchor),
        ])
    }
```

- [ ] **Step 2: Forward the new fields in `SwitcherOverlay`**

In `Sources/CmdTabApp/SwitcherOverlay.swift`, inside the `rows = windows.enumerated().map { idx, win in` closure, replace the `OverlayRowView(...)` construction with:

```swift
            let row = OverlayRowView(
                index: idx,
                icon: icon,
                appName: win.appName,
                title: win.title,
                isMinimized: win.isMinimized,
                isFullScreen: win.isFullScreen,
                isHidden: win.isHidden,
                isOnOtherSpace: win.isOnOtherSpace,
                isDialog: win.isDialog,
                isCurrent: win.isCurrent
            )
```

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds with no errors. (The icons for the three new states will not light up yet — their fields are still `false` until Tasks 3–4 — but minimized/fullScreen/hidden continue to render, now inside the fixed zone.)

- [ ] **Step 4: Commit**

```bash
git add Sources/CmdTabApp/OverlayRowView.swift Sources/CmdTabApp/SwitcherOverlay.swift
git commit -m "feat: fixed-width state-icon zone with six-state priority order"
```

---

### Task 3: Detect dialog and current window (AX only, no CGS)

**Files:**
- Modify: `Sources/CmdTabApp/SystemWindowEnumerator.swift`

**Interfaces:**
- Consumes: `WindowInfo.init(...:isDialog:isCurrent:)` (Task 1).
- Produces: enumerated `WindowInfo`s carry real `isDialog` and `isCurrent`. `isOnOtherSpace` stays `false` (default) until Task 4.

> No unit-test harness for the enumerator (reads live windows); verified by `swift build` and the Task 5 manual pass, consistent with the existing untested code.

- [ ] **Step 1: Add `isDialog` and `isMain` helpers**

In `Sources/CmdTabApp/SystemWindowEnumerator.swift`, add these two methods next to the existing `isMinimized(_:)` / `isFullScreen(_:)` helpers:

```swift
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
```

- [ ] **Step 2: Compute the frontmost pid once per snapshot**

In `snapshot()`, immediately after the `var seen = Set<CGWindowID>()` line, add:

```swift
        // The current window = the AXMain window of whatever app is frontmost.
        // CmdTab's overlay is a non-activating panel, so frontmost stays the
        // user's previously focused app while the switcher is open.
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
```

- [ ] **Step 3: Pass the two new fields into `WindowInfo(...)`**

In `snapshot()`, update the `result.append(WindowInfo(...))` call to add the two new arguments after `isHidden:`:

```swift
                result.append(WindowInfo(
                    id: wid,
                    pid: pid,
                    appName: appName,
                    title: axTitle(axWindow),
                    isMinimized: isMinimized(axWindow),
                    isFullScreen: isFullScreen(axWindow),
                    // App-scoped: macOS hides whole apps (Cmd+H), not individual
                    // windows, so every window of a hidden app reports isHidden.
                    isHidden: app.isHidden,
                    isDialog: isDialog(axWindow),
                    isCurrent: pid == frontmostPID && isMain(axWindow)
                ))
```

- [ ] **Step 4: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds with no errors.

- [ ] **Step 5: Commit**

```bash
git add Sources/CmdTabApp/SystemWindowEnumerator.swift
git commit -m "feat: detect dialog and current-window state via AX"
```

---

### Task 4: Detect on-another-Space via private CGS API (cuttable)

**Files:**
- Modify: `Sources/CGSPrivate/include/CGSPrivate.h`
- Modify: `Sources/CmdTabApp/SystemWindowEnumerator.swift`

**Interfaces:**
- Consumes: `WindowInfo.init(...:isOnOtherSpace:)` (Task 1); the CGS symbols declared in this task.
- Produces: enumerated `WindowInfo`s carry real `isOnOtherSpace`, subject to the suppression rule (false when minimized or full screen).

> This task depends on undocumented private symbols and on "active Space" semantics that vary with multi-display setups. `swift build` succeeding proves only that the symbols link — it does NOT prove the behavior is correct; that is confirmed only by the Task 5 manual pass. If the symbols fail to link or the icon misbehaves, this task can be reverted on its own (it touches only these two files and adds only the `isOnOtherSpace` argument) and the feature still ships with the other five icons.

- [ ] **Step 1: Declare the CGS Spaces symbols**

Replace the contents of `Sources/CGSPrivate/include/CGSPrivate.h` with:

```c
#ifndef CGSPRIVATE_H
#define CGSPRIVATE_H

#include <CoreGraphics/CoreGraphics.h>
#include <ApplicationServices/ApplicationServices.h>

/* Private: maps an AXUIElement window to its CGWindowID.
   Resolves at link time against the ApplicationServices framework. */
AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID *windowID);

/* Private CoreGraphics/SkyLight (CGS) window-Space queries. These resolve at
   link time against the system frameworks, like _AXUIElementGetWindow above.
   Used to tell whether a window lives on a Space other than the active one. */
typedef int CGSConnectionID;
typedef int CGSSpaceID;

enum {
    kCGSSpaceIncludesCurrent = 1 << 0,
    kCGSSpaceIncludesOthers  = 1 << 1,
    kCGSSpaceIncludesUser    = 1 << 2,
    kCGSAllSpacesMask = kCGSSpaceIncludesCurrent | kCGSSpaceIncludesOthers | kCGSSpaceIncludesUser,
};

CGSConnectionID CGSMainConnectionID(void);
CGSSpaceID CGSGetActiveSpace(CGSConnectionID cid);
CFArrayRef CGSCopySpacesForWindows(CGSConnectionID cid, int mask, CFArrayRef windowIDs) CF_RETURNS_RETAINED;

#endif
```

- [ ] **Step 2: Store the CGS connection on the enumerator**

In `Sources/CmdTabApp/SystemWindowEnumerator.swift`, add a stored property next to the existing `private let ownPID = ...`:

```swift
    /// Main CGS connection, reused for Space lookups.
    private let cgsConnection = CGSMainConnectionID()
```

- [ ] **Step 3: Add the `isOnOtherSpace` helper**

Add this method next to the other AX helpers in `SystemWindowEnumerator`:

```swift
    /// True when the window lives on a Space other than the active one.
    /// Returns false on any CGS failure (degrade to "not flagged").
    private func isOnOtherSpace(_ wid: CGWindowID) -> Bool {
        let active = CGSGetActiveSpace(cgsConnection)
        guard active != 0 else { return false }
        let windows = [NSNumber(value: wid)] as CFArray
        guard let spaces = CGSCopySpacesForWindows(cgsConnection, kCGSAllSpacesMask, windows) as? [Int],
              !spaces.isEmpty else { return false }
        return !spaces.contains(Int(active))
    }
```

- [ ] **Step 4: Apply the suppression rule and pass `isOnOtherSpace`**

In `snapshot()`, replace the `result.append(WindowInfo(...))` block from Task 3 with this version, which computes `minimized`/`fullScreen` once so the suppression rule can use them:

```swift
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
```

- [ ] **Step 5: Build to verify it compiles and links**

Run: `swift build`
Expected: Build succeeds with no errors and no linker errors about undefined CGS symbols. (Correct runtime behavior is confirmed in Task 5, not here.)

- [ ] **Step 6: Commit**

```bash
git add Sources/CGSPrivate/include/CGSPrivate.h Sources/CmdTabApp/SystemWindowEnumerator.swift
git commit -m "feat: detect on-another-Space windows via private CGS API"
```

---

### Task 5: Manual verification

**Files:** none (verification only).

- [ ] **Step 1: Build and run the app**

Run: `swift build`, then launch the assembled app (`./Scripts/bundle.sh`, then open `CmdTab.app`) and grant Accessibility permission if prompted.

- [ ] **Step 2: Verify the icons, zone, and suppression**

Arrange windows in known states, invoke Command+Tab, and confirm:
- A minimized window shows `minus.circle`; a full-screen window the expand-arrows; a hidden app's windows `eye.slash` — all still correct.
- A dialog/alert window shows `exclamationmark.bubble`.
- The window you were just in shows `checkmark.circle` (current).
- A window on another desktop/Space shows `macwindow.on.rectangle`, and a minimized or full-screen window does NOT also show that icon (suppression holds). On a multi-display setup, sanity-check the result and note any wrong flags.
- Titles truncate at the **same column** across all rows regardless of icon count; a stateless window shows an empty but reserved zone (no title shift).

- [ ] **Step 3: Run the full test suite**

Run: `swift test`
Expected: PASS — all tests green.

---

## Self-Review

**Spec coverage:**
- Three new `WindowInfo` fields with `= false` defaults → Task 1. ✓
- Fixed 3-slot zone, title pinned to zone leading, priority order, no-placeholder icons, tint/size → Task 2 + Global Constraints. ✓
- Six SF Symbols → Global Constraints + Tasks 2. ✓
- Dialog (AX subrole) + current (frontmost + AXMain) detection → Task 3. ✓
- On-another-Space via CGS, with suppression rule, sequenced last/cuttable → Task 4. ✓
- Model unit test → Task 1; build + manual pass → Tasks 2–5. ✓
- Out-of-scope items (edited/not-responding/zoomed/monitor/always-on-top, list reorder, settings toggle) → not implemented. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code.

**Type consistency:** `OverlayRowView.init(...:isOnOtherSpace:isDialog:isCurrent:)` (Task 2) matches the call in `SwitcherOverlay` (Task 2). `WindowInfo` initializer (Task 1) matches the enumerator calls (Tasks 3, 4). Helper names `isDialog`/`isMain`/`isOnOtherSpace` used consistently. CGS symbol names match between the C header (Task 4 Step 1) and Swift use (Task 4 Steps 2–4). `kCGSAllSpacesMask` defined in the header and used in `isOnOtherSpace`.
