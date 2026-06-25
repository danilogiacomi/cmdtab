import AppKit
import CmdTabCore

/// Flipped so the vertical stack lays out top-to-bottom inside the scroll view.
private final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

final class SwitcherOverlay {
    var onHover: ((Int) -> Void)?
    var onClick: ((Int) -> Void)?

    private var panel: NSPanel?
    private var rows: [OverlayRowView] = []

    /// The overlay appears under wherever the cursor happens to be resting, so
    /// we ignore mouse hover until the user actually moves the mouse (or clicks).
    /// This keeps a stationary cursor from hijacking the keyboard selection.
    private var mouseEngaged = false
    private var mouseMonitor: Any?

    private let rowHeight: CGFloat = 50
    private let width: CGFloat = 520
    private let margin: CGFloat = 4

    func show(_ windows: [WindowInfo], selected: Int) {
        hide()
        guard !windows.isEmpty else { return }

        // Start with the mouse disengaged; the first real movement turns it on.
        mouseEngaged = false
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] _ in self?.engageMouse() }

        // Appear on the screen the mouse is on (not the focused window's screen).
        let targetScreen = screenUnderMouse()
        let full = targetScreen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = targetScreen?.visibleFrame ?? full

        // Clamp the panel to the usable area so a long list never overflows; the
        // rows live in a scroll view, so overflow scrolls instead of growing.
        let naturalHeight = CGFloat(windows.count) * rowHeight + margin * 2
        let panelHeight = min(naturalHeight, visible.height - 80)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: panelHeight),
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

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        // No visible scroller: this is a transient, keyboard-driven HUD whose
        // content usually fits, and the selection auto-scrolls into view. A
        // scroller adds no value here and the first overlay scroller created in
        // the process flashes visible once before auto-hiding (the "scrollbar on
        // first launch" glitch). The clip view still scrolls via wheel/trackpad
        // and scrollToVisible for the rare overflowing list.
        scroll.hasVerticalScroller = false
        scroll.automaticallyAdjustsContentInsets = false
        bg.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: margin),
            scroll.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -margin),
            scroll.topAnchor.constraint(equalTo: bg.topAnchor, constant: margin),
            scroll.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -margin),
            // Hard width cap: without it, a long window title forces the whole
            // panel to grow (and shift off-center). The title truncates instead.
            scroll.widthAnchor.constraint(equalToConstant: width - margin * 2),
        ])

        let stack = FlippedStackView()
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = stack
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])

        rows = windows.enumerated().map { idx, win in
            let icon = NSRunningApplication(processIdentifier: win.pid)?.icon
            let row = OverlayRowView(index: idx, icon: icon, window: win)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.onHover = { [weak self] index in
                guard let self, self.mouseEngaged else { return }
                self.onHover?(index)
            }
            row.onClick = { [weak self] index in
                guard let self else { return }
                self.engageMouse()   // a deliberate click counts as engaging the mouse
                self.onClick?(index)
            }
            stack.addArrangedSubview(row)
            row.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            return row
        }

        // Center on the full screen (geometric center), not the visible frame,
        // so the menu bar / Dock don't push it off-center.
        panel.setFrameOrigin(NSPoint(
            x: full.midX - width / 2,
            y: full.midY - panelHeight / 2
        ))
        panel.orderFrontRegardless()
        self.panel = panel
        highlight(selected)
    }

    func highlight(_ index: Int) {
        for (i, row) in rows.enumerated() { row.setSelected(i == index) }
        guard rows.indices.contains(index) else { return }
        // Defer the scroll out of the current layout pass; calling scrollToVisible
        // while the panel is still laying out triggers _NSDetectedLayoutRecursion.
        let target = rows[index]
        DispatchQueue.main.async { target.scrollToVisible(target.bounds) }
    }

    func hide() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        mouseEngaged = false
        panel?.orderOut(nil)
        panel = nil
        rows = []
    }

    /// The screen the mouse cursor is currently on, so the overlay appears where
    /// the user is looking rather than on the focused window's display.
    private func screenUnderMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) } ?? NSScreen.main
    }

    /// Begin honoring mouse hover; called on the first real mouse movement (or a
    /// click). Removes the movement monitor once engaged.
    private func engageMouse() {
        mouseEngaged = true
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
    }
}
