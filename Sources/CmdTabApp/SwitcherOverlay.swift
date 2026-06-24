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

    private let rowHeight: CGFloat = 44
    private let width: CGFloat = 520
    private let margin: CGFloat = 8

    func show(_ windows: [WindowInfo], selected: Int) {
        hide()
        guard !windows.isEmpty else { return }

        // Clamp the panel to the screen so a long list never overflows; the rows
        // live in a scroll view, so overflow scrolls instead of growing.
        let naturalHeight = CGFloat(windows.count) * rowHeight + margin * 2
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 900
        let panelHeight = min(naturalHeight, screenHeight - 80)

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
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        bg.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: margin),
            scroll.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -margin),
            scroll.topAnchor.constraint(equalTo: bg.topAnchor, constant: margin),
            scroll.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -margin),
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
            panel.setFrameOrigin(NSPoint(x: f.midX - width / 2, y: f.midY - panelHeight / 2))
        }
        panel.orderFrontRegardless()
        self.panel = panel
        highlight(selected)
    }

    func highlight(_ index: Int) {
        for (i, row) in rows.enumerated() { row.setSelected(i == index) }
        if rows.indices.contains(index) {
            rows[index].scrollToVisible(rows[index].bounds)
        }
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        rows = []
    }
}
