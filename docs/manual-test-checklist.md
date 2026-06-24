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
