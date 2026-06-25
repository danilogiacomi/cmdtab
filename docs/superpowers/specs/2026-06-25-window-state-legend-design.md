# Window State Icons legend

Date: 2026-06-25

## Goal

Add a help/legend the user can open to see every window-state icon and what it
means. It opens from a new item in the existing `⌘⇥` menu-bar menu and shows a
small standalone window listing the six state icons with a title and a one-line
explanation each.

Builds on the reserved icon zone
(`docs/superpowers/specs/2026-06-25-window-state-icon-zone-design.md`).

## Single source of truth (DRY refactor)

The six SF Symbol names currently live inline in `OverlayRowView`. The legend
needs the same symbols plus a human title and an explanation, so the icon set
moves to one shared, pure-data list in `CmdTabCore` (no AppKit), consumed by
both the overlay rows and the legend.

```swift
public struct WindowStateDescriptor {
    public let symbolName: String          // e.g. "minus.circle"
    public let title: String               // e.g. "Minimized"
    public let explanation: String         // e.g. "Minimized to the Dock."
    public let isActive: (WindowInfo) -> Bool   // which flag lights it up

    public init(
        symbolName: String,
        title: String,
        explanation: String,
        isActive: @escaping (WindowInfo) -> Bool
    ) { ... }
}

/// All state icons, in the same left→right priority order as the overlay zone.
public let windowStateDescriptors: [WindowStateDescriptor]
```

The list, in order:

| symbolName | title | explanation | isActive |
|---|---|---|---|
| `checkmark.circle` | Current window | The window you're in right now. | `\.isCurrent` |
| `exclamationmark.bubble` | Dialog | A dialog or alert, not a document window. | `\.isDialog` |
| `minus.circle` | Minimized | Minimized to the Dock. | `\.isMinimized` |
| `arrow.up.left.and.arrow.down.right` | Full screen | In macOS full-screen mode. | `\.isFullScreen` |
| `macwindow.on.rectangle` | On another Space | On another desktop; activating it switches Spaces. | `\.isOnOtherSpace` |
| `eye.slash` | Hidden | Its app is hidden (⌘H). | `\.isHidden` |

`isActive` is written as a closure over the corresponding `WindowInfo` flag.

### `OverlayRowView` refactor

`OverlayRowView` stops taking six individual `Bool` parameters. It instead
receives the `WindowInfo` (it already needs `appName`/`title` from it) and
builds its icon stack by iterating `windowStateDescriptors`, rendering an
`NSImageView` for each descriptor whose `isActive(window)` is true — preserving
the existing fixed-width zone, right alignment, priority order, 16pt size, and
`.secondaryLabelColor` tint. `SwitcherOverlay` passes the `WindowInfo` (and the
icon image + index) instead of unpacking the flags.

## Legend window

A new `LegendWindowController` (AppKit, in the app target) owns a single titled,
non-resizable `NSWindow`:

- Content: a vertical stack of six rows, one per `windowStateDescriptor`, each
  `[16pt secondary-tinted SF Symbol]  <title> — <explanation>`. A short header
  line ("Icons shown on the right of each window row:") sits above the list.
- Window title: "Window State Icons". Standard close button; not resizable;
  centered on first open.
- Single instance: the controller is retained by `AppDelegate`. Reopening brings
  the existing window to front rather than creating a second one.
- Because CmdTab is a menu-bar/background app, opening calls
  `NSApp.activate(ignoringOtherApps: true)` and `window.makeKeyAndOrderFront` /
  `orderFrontRegardless()` so the window appears and can be focused/closed.

## Menu wiring

In `AppDelegate.setUpMenuBar()`, add a "Window State Icons…" `NSMenuItem`
between the existing "CmdTab" title item and the separator, targeting an
`@objc` action that lazily creates (or re-fronts) the `LegendWindowController`.

## Testing

- `CmdTabCore` unit tests for `windowStateDescriptors`: exactly six entries; the
  symbolName/title order matches the documented priority order; each `isActive`
  returns true only for a `WindowInfo` with the matching flag set (e.g. a
  `WindowInfo` with `isMinimized = true` activates the "Minimized" descriptor and
  no other).
- Menu wiring and the AppKit legend window are verified by `swift build` and a
  manual pass (no GUI harness in this project), consistent with the existing
  code.

## Out of scope

- An in-overlay (press-a-key) legend — the menu-bar window is the only trigger.
- A preferences/settings window or any persisted UI state.
- Localization of the titles/explanations.
