# Reserved window-state icon zone

Date: 2026-06-25

## Goal

Replace the variable-width state-icon stack on each overlay row with a
**fixed-width reserved zone** on the right, and expand the set of states shown
from three to six. The fixed zone keeps every row's title truncating at the
same column and lines the icons up consistently.

This builds directly on the existing window-state icon column
(`docs/superpowers/specs/2026-06-24-window-state-icons-design.md`).

## States and icons

Six states. The existing three stay; three are new. To avoid redundant or
cluttered icons, three states **suppress** weaker overlapping signals (see
rules below).

| State | SF Symbol | Source | Status |
|---|---|---|---|
| Minimized | `minus.circle` | `AXMinimized` | existing |
| Full screen | `arrow.up.left.and.arrow.down.right` | `AXFullScreen` | existing |
| Hidden (app) | `eye.slash` | `NSRunningApplication.isHidden` | existing |
| On another Space | `macwindow.on.rectangle` | CGS private API | new |
| Dialog / sheet | `exclamationmark.bubble` | `AXSubrole` (dialog/systemDialog) | new |
| Current window | `checkmark.circle` | frontmost app's `AXMain` window | new |

All icons are tinted `.secondaryLabelColor` and shown only when their state is
true (no placeholders), consistent with the existing icons.

### Co-occurrence / suppression rules

- **On another Space** is reported only when the window is **not** minimized
  and **not** full screen. Those two are the more specific signal (a minimized
  window lives in the Dock; a full-screen window has its own Space), so the
  generic "elsewhere" icon would be redundant.
- **Current window** is, by nature, on the active Space, visible, and belongs
  to the frontmost (non-hidden) app — so it never co-occurs with minimized,
  hidden, or on-another-Space. It can co-occur with full screen and dialog.

With these rules, the **realistic maximum number of simultaneous icons on one
row is 3** (e.g. *hidden + dialog + on-another-Space*, or *minimized + hidden +
dialog*). This sizes the reserved zone.

## Reserved zone layout (`OverlayRowView`)

- A **fixed-width** trailing container sized to **3 icon slots**
  (3 × 16pt icons + inter-icon spacing + trailing inset), always present in the
  row whether or not any icon is shown.
- The title label's trailing anchor pins to the **zone's leading edge** (not the
  row edge), so every row truncates its title at the same column regardless of
  how many state icons it carries.
- Icons render in a **fixed priority order**, left → right:
  `current, dialog, minimized, fullScreen, onOtherSpace, hidden`, packed
  right-aligned within the zone.
- Because the zone is now an intentional fixed-width element, the previous
  "empty `NSStackView` always added" cosmetic nit no longer applies — an empty
  zone is by design.

## Model (`WindowInfo`)

Add three stored `Bool` properties, each defaulting to `false` in the
initializer (same pattern as `isFullScreen`/`isHidden`, so existing test
helpers keep compiling):

- `isOnOtherSpace: Bool`
- `isDialog: Bool`
- `isCurrent: Bool`

## Detection (`SystemWindowEnumerator`)

- **`isDialog`** — read `AXSubrole`; true when it equals
  `kAXDialogSubrole` or `kAXSystemDialogSubrole`. (The enumerator already reads
  the subrole for filtering; reuse the value.)
- **`isCurrent`** — the window is current when its owning app is
  `NSWorkspace.shared.frontmostApplication` **and** the window's `AXMain`
  attribute is true. Because CmdTab's overlay is a non-activating panel, the
  frontmost app remains the user's previously focused app while the switcher is
  open.
- **`isOnOtherSpace`** — via CGS: get the window's Space(s) and compare against
  the active Space; true when they differ (and the suppression rule above
  permits it).

### CGS private-API additions (`Sources/CGSPrivate/include/CGSPrivate.h`)

Declare the private symbols needed for Space lookup, alongside the existing
`_AXUIElementGetWindow`:

- `CGSMainConnectionID()` — the main connection.
- `CGSCopySpacesForWindows(connection, mask, windowIDs)` — Space IDs for given
  windows.
- A current-Space query (e.g. `CGSManagedDisplayGetCurrentSpace` per display, or
  `CGSGetActiveSpace`).

These resolve at link time against the system frameworks, exactly like
`_AXUIElementGetWindow` does today.

**Risk and fallback:** these are undocumented private symbols, and "active
Space" is per-display, so multi-monitor setups need care. If the symbols fail to
link or behave unreliably, **"on another Space" is the feature to drop** — the
fixed zone and the other two new icons (dialog, current) do not depend on CGS
and stand on their own. The implementation plan must order the CGS work so it
can be cut without unwinding the rest.

## Testing

- `CmdTabCore` unit tests: cover the three new `WindowInfo` fields (defaults,
  storage, equality), following the existing test style.
- AX subrole / CGS Space detection and the AppKit zone layout have no unit
  harness in this project (established convention); verify by `swift build` and a
  manual GUI pass: confirm each new icon appears for a window in the
  corresponding state, the suppression rules hold, titles truncate at a constant
  column across rows, and a stateless window shows an empty (but reserved) zone.

## Out of scope

- States judged not worth an icon: unsaved/edited document, not-responding
  (beachball), zoomed/maximized (non-full-screen), monitor/display indicator,
  always-on-top.
- Reordering or filtering the window list by state.
- Any user-facing settings toggle.
