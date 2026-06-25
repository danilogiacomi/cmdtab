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
