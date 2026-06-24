import AppKit
import CmdTabCore

final class SwitcherOverlay {
    var onHover: ((Int) -> Void)?
    var onClick: ((Int) -> Void)?

    private var panel: NSPanel?
    private var rows: [OverlayRowView] = []

    func show(_ windows: [WindowInfo], selected: Int) {
        hide()
        guard !windows.isEmpty else { return }

        let rowHeight: CGFloat = 44
        let width: CGFloat = 520
        let height = CGFloat(windows.count) * rowHeight + 16

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
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

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: bg.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -8),
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
            panel.setFrameOrigin(NSPoint(x: f.midX - width / 2, y: f.midY - height / 2))
        }
        panel.orderFrontRegardless()
        self.panel = panel
        highlight(selected)
    }

    func highlight(_ index: Int) {
        for (i, row) in rows.enumerated() { row.setSelected(i == index) }
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        rows = []
    }
}
