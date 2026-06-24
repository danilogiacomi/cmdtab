# Window-state icon column

Date: 2026-06-24

## Goal

Add a right-hand column to each overlay row showing icons for the window's
state: **minimized**, **full screen**, and **hidden**. Icons appear only when
the corresponding state is true; a normal window shows an empty column.

## Non-goals

- Focused/main-window indicator.
- Reordering or filtering the list by state.
- Any user-facing settings toggle.

## Changes

### 1. Model — `Sources/CmdTabCore/WindowInfo.swift`

Add two stored properties alongside the existing `isMinimized`:

- `isFullScreen: Bool`
- `isHidden: Bool`

Both are added to the initializer (after `isMinimized`) with `= false`
defaults, and to the `Equatable` synthesis (automatic). The defaults keep the
existing test helpers in `MRUStoreTests`, `SwitcherControllerTests`, and
`WindowInfoTests` compiling unchanged; the production enumerator passes real
values.

### 2. Detection — `Sources/CmdTabApp/SystemWindowEnumerator.swift`

For each window:

- `isFullScreen` — read the `"AXFullScreen"` AX attribute on the window element.
  There is no public `kAX…` constant for it, so pass the string literal to a
  helper mirroring `isMinimized(_:)` (copy the attribute, cast to `Bool`,
  default `false` on failure).
- `isHidden` — read from the per-app `NSRunningApplication` already in scope in
  the enumeration loop (`app.isHidden`). No extra AX call.

Pass both into the `WindowInfo(...)` construction.

### 3. Rendering — `Sources/CmdTabApp/OverlayRowView.swift`

- Extend `init` to accept `isMinimized`, `isFullScreen`, `isHidden`.
- Add a trailing horizontal `NSStackView` of small `NSImageView`s pinned to the
  row's trailing edge (replacing the title's current trailing pin to the row).
- Re-pin `titleLabel.trailingAnchor` to the state stack's `leadingAnchor` (with
  spacing) so long titles truncate before the icons rather than overlapping.
- Build one `NSImageView` per *true* state, in order minimized, full screen,
  hidden. Skip any state that is false (no placeholder).
- SF Symbols: minimized → `minus.circle`, full screen →
  `arrow.up.left.and.arrow.down.right`, hidden → `eye.slash`. Tint
  `.secondaryLabelColor`. Size to fit the row (~16pt), each with a fixed
  width/height constraint.

### 4. Wiring — `Sources/CmdTabApp/SwitcherOverlay.swift`

`show(_:selected:)` builds each `OverlayRowView` from a `WindowInfo`; forward
the three booleans (`win.isMinimized`, `win.isFullScreen`, `win.isHidden`) into
the initializer.

## Testing

- `CmdTabCore` unit tests: add coverage for the new `WindowInfo` fields
  (construction + equality), following the existing test style.
- AX detection and AppKit rendering have no unit harness today; verify by
  building (`swift build`) and running the app, checking that minimized,
  full-screen, and hidden windows show the expected icons and normal windows
  show none.
