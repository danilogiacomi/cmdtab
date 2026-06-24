# Window-state icon column Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a right-hand column of icons to each overlay row indicating window state — minimized, full screen, and hidden.

**Architecture:** Extend `WindowInfo` (in `CmdTabCore`) with two new boolean fields. `SystemWindowEnumerator` populates them from AX / `NSRunningApplication`. `OverlayRowView` renders a trailing horizontal stack of SF Symbol icons, one per active state. `SwitcherOverlay` forwards the fields when building rows.

**Tech Stack:** Swift, AppKit, ApplicationServices (Accessibility API), XCTest.

## Global Constraints

- Swift, targeting macOS. Follow the Swift API Design Guidelines.
- New `WindowInfo` initializer parameters must have `= false` defaults so existing test helpers compile unchanged.
- Icons appear only when their state is true — no placeholder/greyed icons.
- SF Symbols: minimized → `minus.circle`, full screen → `arrow.up.left.and.arrow.down.right`, hidden → `eye.slash`, tinted `.secondaryLabelColor`.

---

### Task 1: Extend `WindowInfo` model

**Files:**
- Modify: `Sources/CmdTabCore/WindowInfo.swift`
- Test: `Tests/CmdTabCoreTests/WindowInfoTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `WindowInfo.init(id:pid:appName:title:isMinimized:isFullScreen:isHidden:)` where `isFullScreen: Bool = false` and `isHidden: Bool = false`; stored properties `isFullScreen: Bool` and `isHidden: Bool`.

- [ ] **Step 1: Write the failing test**

Add this test to `Tests/CmdTabCoreTests/WindowInfoTests.swift`:

```swift
    func testStateFlagsDefaultFalseAndStore() {
        let plain = WindowInfo(id: 1, pid: 10, appName: "Safari", title: "Inbox", isMinimized: false)
        XCTAssertFalse(plain.isFullScreen)
        XCTAssertFalse(plain.isHidden)

        let flagged = WindowInfo(
            id: 2, pid: 10, appName: "Safari", title: "Inbox",
            isMinimized: true, isFullScreen: true, isHidden: true
        )
        XCTAssertTrue(flagged.isMinimized)
        XCTAssertTrue(flagged.isFullScreen)
        XCTAssertTrue(flagged.isHidden)
        XCTAssertNotEqual(plain, flagged)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter WindowInfoTests`
Expected: FAIL — compile error, `WindowInfo` has no parameter `isFullScreen`.

- [ ] **Step 3: Write minimal implementation**

Replace the body of `Sources/CmdTabCore/WindowInfo.swift`'s struct with the new fields:

```swift
public struct WindowInfo: Equatable, Identifiable {
    public let id: CGWindowID
    public let pid: pid_t
    public let appName: String
    public let title: String
    public let isMinimized: Bool
    public let isFullScreen: Bool
    public let isHidden: Bool

    public init(
        id: CGWindowID,
        pid: pid_t,
        appName: String,
        title: String,
        isMinimized: Bool,
        isFullScreen: Bool = false,
        isHidden: Bool = false
    ) {
        self.id = id
        self.pid = pid
        self.appName = appName
        self.title = title
        self.isMinimized = isMinimized
        self.isFullScreen = isFullScreen
        self.isHidden = isHidden
    }

    /// What the overlay renders when the window has no title.
    public var displayTitle: String { title.isEmpty ? appName : title }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CmdTabCoreTests`
Expected: PASS — all CmdTabCore tests green (existing helpers still compile via defaults).

- [ ] **Step 5: Commit**

```bash
git add Sources/CmdTabCore/WindowInfo.swift Tests/CmdTabCoreTests/WindowInfoTests.swift
git commit -m "feat: add isFullScreen/isHidden to WindowInfo"
```

---

### Task 2: Populate state in `SystemWindowEnumerator`

**Files:**
- Modify: `Sources/CmdTabApp/SystemWindowEnumerator.swift`

**Interfaces:**
- Consumes: `WindowInfo.init(...:isFullScreen:isHidden:)` from Task 1.
- Produces: each enumerated `WindowInfo` carries real `isFullScreen` (from the `"AXFullScreen"` attribute) and `isHidden` (from `NSRunningApplication.isHidden`).

> No unit-test harness exists for AX enumeration (it reads live system windows), so this task is verified by build, consistent with the existing untested enumerator. The deliverable is a compiling, correct construction.

- [ ] **Step 1: Add an `isFullScreen` helper**

Add this method to `SystemWindowEnumerator`, next to `isMinimized(_:)`:

```swift
    private func isFullScreen(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXFullScreen" as CFString, &value) == .success
        else { return false }
        return (value as? Bool) == true
    }
```

- [ ] **Step 2: Pass the new fields into `WindowInfo(...)`**

In `snapshot()`, change the `result.append(WindowInfo(...))` call to include the new arguments. `app` (the `NSRunningApplication`) is already in scope in the loop:

```swift
                result.append(WindowInfo(
                    id: wid,
                    pid: pid,
                    appName: appName,
                    title: axTitle(axWindow),
                    isMinimized: isMinimized(axWindow),
                    isFullScreen: isFullScreen(axWindow),
                    isHidden: app.isHidden
                ))
```

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds with no errors.

- [ ] **Step 4: Commit**

```bash
git add Sources/CmdTabApp/SystemWindowEnumerator.swift
git commit -m "feat: detect full-screen and hidden window state"
```

---

### Task 3: Render the state-icon column in `OverlayRowView`

**Files:**
- Modify: `Sources/CmdTabApp/OverlayRowView.swift`

**Interfaces:**
- Consumes: nothing from other tasks (takes plain `Bool`s).
- Produces: `OverlayRowView.init(index:icon:appName:title:isMinimized:isFullScreen:isHidden:)` — three new trailing `Bool` parameters consumed by Task 4.

> AppKit view layout has no unit harness here; verified by build (this task) and run (Task 4). The deliverable is a compiling view that lays out the icon stack.

- [ ] **Step 1: Add the state parameters and build the icon stack**

Replace the `init` and the constraint block in `Sources/CmdTabApp/OverlayRowView.swift`. The full updated initializer:

```swift
    init(
        index: Int,
        icon: NSImage?,
        appName: String,
        title: String,
        isMinimized: Bool,
        isFullScreen: Bool,
        isHidden: Bool
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

        // Trailing column of state icons; only active states get a view.
        let states = NSStackView()
        states.orientation = .horizontal
        states.spacing = 6
        states.translatesAutoresizingMaskIntoConstraints = false
        states.setContentHuggingPriority(.required, for: .horizontal)
        states.setContentCompressionResistancePriority(.required, for: .horizontal)
        let symbols: [(Bool, String, String)] = [
            (isMinimized, "minus.circle", "Minimized"),
            (isFullScreen, "arrow.up.left.and.arrow.down.right", "Full screen"),
            (isHidden, "eye.slash", "Hidden"),
        ]
        for (active, symbol, label) in symbols where active {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            let view = NSImageView(image: image ?? NSImage())
            view.contentTintColor = .secondaryLabelColor
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalToConstant: 16).isActive = true
            view.heightAnchor.constraint(equalToConstant: 16).isActive = true
            states.addArrangedSubview(view)
        }

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(states)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: states.leadingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            states.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            states.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: FAIL — `SwitcherOverlay` still calls the old initializer (missing arguments). This is expected; Task 4 fixes the call site. To confirm the failure is *only* the call site, check the error names `OverlayRowView` arguments in `SwitcherOverlay.swift`.

> Note: Tasks 3 and 4 share a single compile cycle. Do not commit Task 3 alone (the build is red until Task 4). Proceed directly to Task 4, then commit both together at Task 4 Step 3.

---

### Task 4: Forward state fields when building rows

**Files:**
- Modify: `Sources/CmdTabApp/SwitcherOverlay.swift`

**Interfaces:**
- Consumes: `OverlayRowView.init(index:icon:appName:title:isMinimized:isFullScreen:isHidden:)` from Task 3; `WindowInfo.isFullScreen`/`isHidden` from Task 1.
- Produces: rows constructed with live state flags.

- [ ] **Step 1: Pass the state flags into the row initializer**

In `show(_:selected:)`, update the `OverlayRowView(...)` construction inside the `rows = windows.enumerated().map { ... }` closure:

```swift
            let row = OverlayRowView(
                index: idx,
                icon: icon,
                appName: win.appName,
                title: win.title,
                isMinimized: win.isMinimized,
                isFullScreen: win.isFullScreen,
                isHidden: win.isHidden
            )
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/CmdTabApp/OverlayRowView.swift Sources/CmdTabApp/SwitcherOverlay.swift
git commit -m "feat: render window-state icon column in overlay rows"
```

---

### Task 5: Manual verification

**Files:** none (verification only).

- [ ] **Step 1: Build and run the app**

Run: `swift build` then launch the assembled app (e.g. `./Scripts/bundle.sh` then open `CmdTab.app`, or run the built binary). Grant Accessibility permission if prompted.

- [ ] **Step 2: Verify the icons**

Set up windows in known states, then invoke Command+Tab and confirm:
- A minimized window shows the `minus.circle` icon.
- A full-screen window shows the expand-arrows icon.
- A window whose app is hidden (Cmd+H) shows the `eye.slash` icon.
- A normal window shows no state icons.
- A long title truncates with `…` and never overlaps the icons.

- [ ] **Step 3: Run the full test suite**

Run: `swift test`
Expected: PASS — all tests green.

---

## Self-Review

**Spec coverage:**
- Model fields `isFullScreen`/`isHidden` → Task 1. ✓
- AX `AXFullScreen` + `NSRunningApplication.isHidden` detection → Task 2. ✓
- Trailing icon stack, title re-pin, icon-only-when-active, SF Symbols, tint → Task 3. ✓
- Wiring from `WindowInfo` → Task 4. ✓
- Unit test for model fields → Task 1; build/run verification → Tasks 2, 3, 5. ✓
- Non-goals (focused indicator, reordering, settings toggle) → not implemented. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code.

**Type consistency:** `OverlayRowView.init(index:icon:appName:title:isMinimized:isFullScreen:isHidden:)` defined in Task 3 matches the call in Task 4. `WindowInfo` initializer in Task 1 matches the call in Task 2. `isFullScreen(_:)` helper named consistently.
