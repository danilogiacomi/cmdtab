import AppKit

final class OverlayRowView: NSView {
    var onHover: ((Int) -> Void)?
    var onClick: ((Int) -> Void)?

    private let index: Int
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")

    init(
        index: Int,
        icon: NSImage?,
        appName: String,
        title: String,
        isMinimized: Bool,
        isFullScreen: Bool,
        isHidden: Bool
    ) {
        self.index = index
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8

        iconView.image = icon
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let shown = title.isEmpty ? appName : "\(appName) — \(title)"
        titleLabel.stringValue = shown
        titleLabel.lineBreakMode = .byTruncatingTail
        // Yield rather than force the row (and panel) wider for long titles.
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.font = .systemFont(ofSize: 16)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Trailing column of state icons; only active states get a view.
        let states = NSStackView()
        states.orientation = .horizontal
        states.spacing = 6
        states.translatesAutoresizingMaskIntoConstraints = false
        states.setContentHuggingPriority(.required, for: .horizontal)
        states.setContentCompressionResistancePriority(.required, for: .horizontal)
        let symbols: [(Bool, String, String)] = [
            (isMinimized, "minus.circle", "Minimized"),
            (isFullScreen, "arrow.up.left.and.arrow.down.right", "Full screen"),
            (isHidden, "eye.slash", "Hidden"),
        ]
        for (active, symbol, label) in symbols where active {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            let view = NSImageView(image: image ?? NSImage())
            view.contentTintColor = .secondaryLabelColor
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalToConstant: 16).isActive = true
            view.heightAnchor.constraint(equalToConstant: 16).isActive = true
            states.addArrangedSubview(view)
        }

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(states)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: states.leadingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            states.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            states.centerYAnchor.constraint(equalTo: centerYAnchor),
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
