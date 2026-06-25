# Window State Icons legend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a menu-bar-opened legend window that lists every window-state icon and explains its meaning, backed by a single shared icon descriptor list.

**Architecture:** A pure-data `windowStateDescriptors` list moves to `CmdTabCore` (symbol name + title + explanation + an `isActive(WindowInfo)` predicate). `OverlayRowView` is refactored to take a `WindowInfo` and iterate that list instead of six bools. A new `LegendWindowController` in the app target renders the same list in a single-instance window, opened from a new `⌘⇥`-menu item.

**Tech Stack:** Swift, AppKit, XCTest.

## Global Constraints

- Swift, targeting macOS. Follow the Swift API Design Guidelines.
- One shared source of truth for the icons: `windowStateDescriptors` in `CmdTabCore`. No SF Symbol name may be duplicated outside it.
- Descriptor order = the overlay's left→right priority order: current, dialog, minimized, fullScreen, onOtherSpace, hidden.
- Icon rendering: 16×16 `NSImageView`, `.secondaryLabelColor` tint, image via `NSImage(systemSymbolName:accessibilityDescription:)` with a `?? NSImage()` fallback.
- The legend is a single-instance, titled, non-resizable window; reopening re-fronts it. CmdTab is a menu-bar/background app, so showing it calls `NSApp.activate(ignoringOtherApps: true)` then `makeKeyAndOrderFront`.

---

### Task 1: Shared `windowStateDescriptors` in CmdTabCore

**Files:**
- Create: `Sources/CmdTabCore/WindowStateDescriptor.swift`
- Test: `Tests/CmdTabCoreTests/WindowStateDescriptorTests.swift`

**Interfaces:**
- Consumes: `WindowInfo` (existing) and its `isCurrent`/`isDialog`/`isMinimized`/`isFullScreen`/`isOnOtherSpace`/`isHidden` flags.
- Produces: `public struct WindowStateDescriptor { let symbolName: String; let title: String; let explanation: String; let isActive: (WindowInfo) -> Bool }` and `public let windowStateDescriptors: [WindowStateDescriptor]` (6 entries, priority order).

- [ ] **Step 1: Write the failing test**

Create `Tests/CmdTabCoreTests/WindowStateDescriptorTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import CmdTabCore

final class WindowStateDescriptorTests: XCTestCase {
    func testDescriptorCountAndOrder() {
        XCTAssertEqual(windowStateDescriptors.count, 6)
        XCTAssertEqual(
            windowStateDescriptors.map(\.symbolName),
            [
                "checkmark.circle",
                "exclamationmark.bubble",
                "minus.circle",
                "arrow.up.left.and.arrow.down.right",
                "macwindow.on.rectangle",
                "eye.slash",
            ]
        )
    }

    func testEachDescriptorActivatesOnlyForItsFlag() {
        let cases: [(String, WindowInfo)] = [
            ("checkmark.circle", make(isCurrent: true)),
            ("exclamationmark.bubble", make(isDialog: true)),
            ("minus.circle", make(isMinimized: true)),
            ("arrow.up.left.and.arrow.down.right", make(isFullScreen: true)),
            ("macwindow.on.rectangle", make(isOnOtherSpace: true)),
            ("eye.slash", make(isHidden: true)),
        ]
        for (symbol, window) in cases {
            let active = windowStateDescriptors.filter { $0.isActive(window) }
            XCTAssertEqual(active.count, 1, "\(symbol): expected exactly one active descriptor")
            XCTAssertEqual(active.first?.symbolName, symbol)
        }
    }

    func testNoDescriptorActivatesForPlainWindow() {
        let plain = make()
        XCTAssertTrue(windowStateDescriptors.allSatisfy { !$0.isActive(plain) })
    }

    private func make(
        isMinimized: Bool = false,
        isFullScreen: Bool = false,
        isHidden: Bool = false,
        isOnOtherSpace: Bool = false,
        isDialog: Bool = false,
        isCurrent: Bool = false
    ) -> WindowInfo {
        WindowInfo(
            id: 1, pid: 1, appName: "App", title: "T",
            isMinimized: isMinimized, isFullScreen: isFullScreen, isHidden: isHidden,
            isOnOtherSpace: isOnOtherSpace, isDialog: isDialog, isCurrent: isCurrent
        )
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter WindowStateDescriptorTests`
Expected: FAIL — compile error, `windowStateDescriptors` is undefined.

- [ ] **Step 3: Write the implementation**

Create `Sources/CmdTabCore/WindowStateDescriptor.swift`:

```swift
import Foundation

/// Describes one window-state icon: the SF Symbol to draw, how to label it in
/// the legend, and which `WindowInfo` flag turns it on. The single source of
/// truth shared by the overlay rows and the legend window.
public struct WindowStateDescriptor {
    public let symbolName: String
    public let title: String
    public let explanation: String
    public let isActive: (WindowInfo) -> Bool

    public init(
        symbolName: String,
        title: String,
        explanation: String,
        isActive: @escaping (WindowInfo) -> Bool
    ) {
        self.symbolName = symbolName
        self.title = title
        self.explanation = explanation
        self.isActive = isActive
    }
}

/// All window-state icons, in the same left→right priority order the overlay
/// renders them in.
public let windowStateDescriptors: [WindowStateDescriptor] = [
    WindowStateDescriptor(
        symbolName: "checkmark.circle",
        title: "Current window",
        explanation: "The window you're in right now.",
        isActive: { $0.isCurrent }
    ),
    WindowStateDescriptor(
        symbolName: "exclamationmark.bubble",
        title: "Dialog",
        explanation: "A dialog or alert, not a document window.",
        isActive: { $0.isDialog }
    ),
    WindowStateDescriptor(
        symbolName: "minus.circle",
        title: "Minimized",
        explanation: "Minimized to the Dock.",
        isActive: { $0.isMinimized }
    ),
    WindowStateDescriptor(
        symbolName: "arrow.up.left.and.arrow.down.right",
        title: "Full screen",
        explanation: "In macOS full-screen mode.",
        isActive: { $0.isFullScreen }
    ),
    WindowStateDescriptor(
        symbolName: "macwindow.on.rectangle",
        title: "On another Space",
        explanation: "On another desktop; activating it switches Spaces.",
        isActive: { $0.isOnOtherSpace }
    ),
    WindowStateDescriptor(
        symbolName: "eye.slash",
        title: "Hidden",
        explanation: "Its app is hidden (⌘H).",
        isActive: { $0.isHidden }
    ),
]
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CmdTabCoreTests`
Expected: PASS — all CmdTabCore tests green.

- [ ] **Step 5: Commit**

```bash
git add Sources/CmdTabCore/WindowStateDescriptor.swift Tests/CmdTabCoreTests/WindowStateDescriptorTests.swift
git commit -m "feat: add shared windowStateDescriptors list to CmdTabCore"
```

---

### Task 2: Refactor `OverlayRowView` to consume the descriptors

**Files:**
- Modify: `Sources/CmdTabApp/OverlayRowView.swift`
- Modify: `Sources/CmdTabApp/SwitcherOverlay.swift`

**Interfaces:**
- Consumes: `windowStateDescriptors` and `WindowInfo` (Task 1).
- Produces: `OverlayRowView.init(index: Int, icon: NSImage?, window: WindowInfo)`.

> Two files, one compile cycle: changing the initializer breaks the `SwitcherOverlay` call site. Edit both, build once, commit once. No unit harness for these AppKit files; verified by `swift build` + Task 4 manual pass.

- [ ] **Step 1: Rewrite `OverlayRowView`**

Replace the entire contents of `Sources/CmdTabApp/OverlayRowView.swift` with:

```swift
import AppKit
import CmdTabCore

final class OverlayRowView: NSView {
    var onHover: ((Int) -> Void)?
    var onClick: ((Int) -> Void)?

    private let index: Int
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")

    init(index: Int, icon: NSImage?, window: WindowInfo) {
        self.index = index
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8

        iconView.image = icon
        // App icons report a small natural size; without this the default
        // .scaleProportionallyDown refuses to enlarge them past it, so the
        // icon frame can grow with no visible effect.
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let shown = window.title.isEmpty ? window.appName : "\(window.appName) — \(window.title)"
        titleLabel.stringValue = shown
        titleLabel.lineBreakMode = .byTruncatingTail
        // Yield rather than force the row (and panel) wider for long titles.
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.font = .systemFont(ofSize: 16)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Fixed-width reserved zone (3 icon slots), so every row's title
        // truncates at the same column. Active icons render right-aligned
        // inside it, in the shared priority order.
        let zoneWidth: CGFloat = 3 * 16 + 2 * 6   // 3 slots + inter-icon spacing
        let zone = NSView()
        zone.translatesAutoresizingMaskIntoConstraints = false

        let icons = NSStackView()
        icons.orientation = .horizontal
        icons.spacing = 6
        icons.translatesAutoresizingMaskIntoConstraints = false

        for descriptor in windowStateDescriptors where descriptor.isActive(window) {
            let image = NSImage(systemSymbolName: descriptor.symbolName, accessibilityDescription: descriptor.title)
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

- [ ] **Step 2: Update the call site in `SwitcherOverlay`**

In `Sources/CmdTabApp/SwitcherOverlay.swift`, inside the `rows = windows.enumerated().map { idx, win in` closure, replace the `OverlayRowView(...)` construction (currently passing `index`, `icon`, `appName`, `title`, and the six flags) with:

```swift
            let row = OverlayRowView(index: idx, icon: icon, window: win)
```

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds with no errors.

- [ ] **Step 4: Commit**

```bash
git add Sources/CmdTabApp/OverlayRowView.swift Sources/CmdTabApp/SwitcherOverlay.swift
git commit -m "refactor: OverlayRowView renders icons from shared descriptors"
```

---

### Task 3: Legend window + menu item

**Files:**
- Create: `Sources/CmdTabApp/LegendWindowController.swift`
- Modify: `Sources/CmdTabApp/AppDelegate.swift`

**Interfaces:**
- Consumes: `windowStateDescriptors` (Task 1).
- Produces: `LegendWindowController` with `func show()`; an `@objc` `showLegend()` action and a "Window State Icons…" menu item in `AppDelegate`.

> No unit harness for AppKit/menu code; verified by `swift build` + Task 4 manual pass.

- [ ] **Step 1: Create the legend window controller**

Create `Sources/CmdTabApp/LegendWindowController.swift`:

```swift
import AppKit
import CmdTabCore

/// Single-instance window that lists the window-state icons and what they mean.
final class LegendWindowController {
    private var window: NSWindow?

    /// Show the legend, creating it on first use or re-fronting an existing one.
    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = makeWindow()
        self.window = window
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let content = makeContentView()
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Window State Icons"
        window.isReleasedWhenClosed = false
        window.contentView = content
        window.setContentSize(content.fittingSize)
        return window
    }

    private func makeContentView() -> NSView {
        let header = NSTextField(labelWithString: "Icons shown on the right of each window row:")
        header.font = .systemFont(ofSize: 12)
        header.textColor = .secondaryLabelColor

        let rows = windowStateDescriptors.map(makeRow)

        let stack = NSStackView(views: [header] + rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func makeRow(_ descriptor: WindowStateDescriptor) -> NSView {
        let image = NSImage(systemSymbolName: descriptor.symbolName, accessibilityDescription: descriptor.title)
        let iconView = NSImageView(image: image ?? NSImage())
        iconView.contentTintColor = .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 16).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 16).isActive = true

        let label = NSTextField(labelWithString: "\(descriptor.title) — \(descriptor.explanation)")
        label.font = .systemFont(ofSize: 13)

        let row = NSStackView(views: [iconView, label])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        return row
    }
}
```

- [ ] **Step 2: Add the controller property and menu item in `AppDelegate`**

In `Sources/CmdTabApp/AppDelegate.swift`, add a stored property next to the existing `private var statusItem: NSStatusItem?`:

```swift
    private let legend = LegendWindowController()
```

Then in `setUpMenuBar()`, insert the legend item between the "CmdTab" title item and the separator. Replace:

```swift
        menu.addItem(NSMenuItem(title: "CmdTab", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
```

with:

```swift
        menu.addItem(NSMenuItem(title: "CmdTab", action: nil, keyEquivalent: ""))
        let legendItem = NSMenuItem(title: "Window State Icons…", action: #selector(showLegend), keyEquivalent: "")
        legendItem.target = self
        menu.addItem(legendItem)
        menu.addItem(.separator())
```

- [ ] **Step 3: Add the action method in `AppDelegate`**

Add this method to `AppDelegate` (e.g. next to `@objc private func quit()`):

```swift
    @objc private func showLegend() {
        legend.show()
    }
```

- [ ] **Step 4: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds with no errors.

- [ ] **Step 5: Commit**

```bash
git add Sources/CmdTabApp/LegendWindowController.swift Sources/CmdTabApp/AppDelegate.swift
git commit -m "feat: add Window State Icons legend window and menu item"
```

---

### Task 4: Manual verification

**Files:** none (verification only).

- [ ] **Step 1: Build and run the app**

Run: `swift build`, then `./Scripts/bundle.sh debug && open build/CmdTab.app`. Grant Accessibility permission if prompted.

- [ ] **Step 2: Verify the legend**

- Click the `⌘⇥` menu-bar item → it shows a "Window State Icons…" entry between "CmdTab" and "Quit CmdTab".
- Choosing it opens a titled "Window State Icons" window listing all six icons, each with its symbol, title, and explanation, in the order current → dialog → minimized → full screen → on another Space → hidden.
- The window is not resizable, can be closed, and choosing the menu item again re-fronts the same window (no second window appears).

- [ ] **Step 3: Verify the overlay still works**

Invoke `⌘Tab` and confirm the state icons still render correctly in the overlay rows (the refactor didn't change behavior): minimized/full-screen/hidden/dialog/current/another-Space icons appear as before, in the same priority order and fixed zone.

- [ ] **Step 4: Run the full test suite**

Run: `swift test`
Expected: PASS — all tests green.

---

## Self-Review

**Spec coverage:**
- Shared `windowStateDescriptors` in CmdTabCore (pure data, 6 entries, priority order) → Task 1. ✓
- `OverlayRowView` refactor to consume the list via `WindowInfo` → Task 2. ✓
- `LegendWindowController` single-instance titled non-resizable window with header + six rows, background-app activation → Task 3 Step 1. ✓
- Menu item "Window State Icons…" between CmdTab and the separator → Task 3 Steps 2–3. ✓
- Unit tests for descriptors (count, order, isActive mapping) → Task 1; build + manual pass → Tasks 2–4. ✓
- Out-of-scope (in-overlay key trigger, settings window, localization) → not implemented. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code.

**Type consistency:** `windowStateDescriptors`/`WindowStateDescriptor` (Task 1) are used identically in Tasks 2 and 3. `OverlayRowView.init(index:icon:window:)` (Task 2 Step 1) matches the call site (Task 2 Step 2). `LegendWindowController.show()` (Task 3 Step 1) matches `showLegend()`'s call (Task 3 Step 3). Symbol names/titles/explanations match the spec table exactly.
