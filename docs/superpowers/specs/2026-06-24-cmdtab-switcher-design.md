# CmdTab — Plasma-style Window Switcher — Design

**Date:** 2026-06-24
**Status:** Approved (design); pending implementation plan
**Author:** brainstormed with Claude Code

## Summary

CmdTab is a macOS background agent app that replaces the default `Command+Tab`
application switcher with a **window switcher**: it lists **every open window
individually** — never grouped by application — in the spirit of the KDE Plasma
window switchers (`KWin.Switcher`). The user holds `⌘`, taps `Tab` to cycle through
windows, and releases `⌘` to activate the selected one.

## Goals

- Show **all** open windows with no exceptions: normal, minimized, hidden-app, and
  windows on **other Mission Control Spaces / full-screen apps**.
- One entry per window, **not grouped by app** (unlike the native switcher).
- Intercept `⌘Tab` so the native switcher never appears.
- Fast, keyboard-driven overlay with sensible most-recently-used (MRU) ordering.

## Non-goals

- **Live thumbnails** (Plasma "Thumbnails"/"Cover Switch" look). v1 uses **icon +
  window title** only. Thumbnails (requiring Screen Recording + ScreenCaptureKit) are
  explicitly out of scope for v1 and may be a future phase.
- **Mac App Store distribution** — impossible: sandboxing forbids the private APIs and
  Accessibility access required. Not pursued.
- **Notarization / Developer ID signing** — not needed; this is a **personal-use** app,
  ad-hoc signed, permissions granted manually.
- Grouping, app-level switching, or `⌘\`` same-app cycling (irrelevant once windows are
  ungrouped).

## Constraints & platform realities

- **Target OS:** macOS 14 Sonoma / 15 Sequoia. Private-API specifics pinned to the
  user's exact build during implementation (`sw_vers` check).
- **Replacing `⌘Tab`** requires a global **`CGEventTap`** (the only way to get the
  hold-to-cycle gesture and suppress the native switcher).
- **Full window coverage** requires **private CoreGraphics (CGS) APIs**
  (`CGSCopyWindowsWithOptionsAndTags`, `_AXUIElementGetWindow`); public APIs cannot see
  other Spaces. This is the documented AltTab approach.
- **Permissions:** Accessibility (required); Input Monitoring (if the event tap demands
  it). No Screen Recording.
- **App cannot be sandboxed.**

## Prior art

[AltTab](https://github.com/lwouis/alt-tab-macos) implements essentially this feature
set and validates the approach (hybrid AX + CGS, CGEventTap interception). Used as a
reference, not a dependency.

## Architecture

Hybrid window enumeration (**Option C**): private CGS APIs discover the full window set
across all Spaces; Accessibility (AX) enriches each window with title/icon/state and
performs reliable raising. Fragile private-API code is quarantined behind a single
`WindowEnumerator` interface so OS-version breakage is contained to one module.

### Components

| Component | Responsibility | Layer |
|---|---|---|
| `AgentApp` (AppDelegate) | `LSUIElement` background app, no Dock icon; optional menu-bar item (quit / permission status); wires dependencies | shell |
| `PermissionsManager` | Check/request Accessibility (+ Input Monitoring if needed); first-run guidance; poll until granted | thin adapter |
| `HotkeyMonitor` | `CGEventTap` detecting the Cmd+Tab gesture; swallows events so the native switcher never appears; self-heals on `tapDisabledByTimeout` | adapter (protocol) |
| `WindowEnumerator` | **Isolated private-API module.** CGS discovery across all Spaces + AX enrichment (title, icon, pid, minimized, AX element ref) | adapter (protocol) |
| `MRUStore` | Most-recently-used ordering; observes focus/app-activation changes | **pure logic** |
| `SwitcherController` | Orchestrates: snapshot → order → show → advance selection → commit/cancel | **pure-ish logic** |
| `SwitcherOverlay` | Borderless non-activating `NSPanel`, icon+title rows, selection highlight, keyboard + mouse | thin (AppKit) |
| `WindowActivator` | Raise chosen window (`AXRaise` + activate owning app), following it to its Space | adapter (protocol) |

`HotkeyMonitor`, `WindowEnumerator`, and `WindowActivator` are **protocols**, so
`SwitcherController` + `MRUStore` + selection logic are pure and unit-testable with
injected fake windows.

### Data model

`WindowInfo`: stable window id (CGS), owning pid, app name, app icon, window title,
minimized flag, Space identifier, and an AX element reference for raising.

### Data flow

1. `⌘` held + `Tab` keydown → `HotkeyMonitor` → `SwitcherController.trigger()`.
2. Controller asks `WindowEnumerator.snapshot()`, orders via `MRUStore`.
3. `SwitcherOverlay.show(list, selectedIndex)` — selection starts on the **previous**
   window (MRU index 1).
4. Further `Tab` → advance; `⌘+Shift+Tab` → backward; arrows/mouse → move selection.
   All swallowed while active.
5. `⌘` released → `SwitcherController.commit()` → `WindowActivator.activate(window)` →
   overlay hides. `Esc` → cancel, hide, no activation.

## Gesture semantics (v1 defaults)

- Hold `⌘`, press `Tab` → overlay opens, selection on previously-used window (MRU).
- `Tab` advances; `⌘+Shift+Tab` reverses.
- `← → / ↑ ↓` move selection; mouse hover highlights, click commits.
- Release `⌘` activates selection; `Esc` cancels.
- Keys swallowed only while the gesture is active.

## App shape, build & permissions

- **AppKit** agent app; **Xcode project** (app bundle + Info.plist `LSUIElement` + usage
  strings + entitlements + ad-hoc signing). Build/run via `xcodebuild` or Xcode.
  *(Updates the AGENTS.md placeholder commands from SwiftPM to xcodebuild.)*
- Overlay: `NSPanel` (`.nonactivatingPanel`), high window level, `collectionBehavior`
  set to appear over all Spaces and full-screen apps.
- **First-run permission flow:** detect missing Accessibility, show an instructions
  window with an "Open Settings" button, poll until granted, then proceed.

## Error handling & resilience

- **Event tap self-heals**: listen for `tapDisabledByTimeout` / `tapDisabledByUserInput`
  and re-enable.
- **Graceful degradation**: if private CGS calls fail (e.g. OS update), fall back to an
  AX-only current-Space list instead of crashing, and log.
- **Activation fallback**: if a window won't raise, activate its owning app.

## Testing strategy

- **Unit tested (pure):** `MRUStore` ordering, `SwitcherController` selection advance /
  wraparound / commit / cancel, window-list filtering — all against fake `WindowInfo`
  fixtures injected through the adapter protocols.
- **Manually verified (system-dependent):** `WindowEnumerator` (private APIs),
  `HotkeyMonitor` (event tap), `WindowActivator` — via a manual test checklist covering
  minimized windows, windows on other Spaces, and hidden apps.

## Open items for implementation

- Confirm exact macOS build (`sw_vers`) and pin CGS symbol behavior accordingly.
- Determine whether Input Monitoring is required in addition to Accessibility on the
  target build.
- Choose menu-bar UI minimum (quit + permission status at least).
