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
