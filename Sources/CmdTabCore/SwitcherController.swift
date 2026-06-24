import CoreGraphics

public final class SwitcherController {
    public private(set) var isVisible = false
    public private(set) var windows: [WindowInfo] = []
    public private(set) var selectedIndex = 0

    public var onShow: (([WindowInfo], Int) -> Void)?
    public var onSelectionChange: ((Int) -> Void)?
    public var onHide: (() -> Void)?

    private let enumerator: WindowEnumerating
    private let activator: WindowActivating
    private let mru: MRUStore

    public init(enumerator: WindowEnumerating, activator: WindowActivating, mru: MRUStore) {
        self.enumerator = enumerator
        self.activator = activator
        self.mru = mru
    }

    public func handle(_ command: SwitcherCommand) {
        switch command {
        case .show:
            if isVisible { advance(by: 1) } else { present() }
        case .next, .moveRight, .moveDown:
            guard isVisible else { return }
            advance(by: 1)
        case .previous, .moveLeft, .moveUp:
            guard isVisible else { return }
            advance(by: -1)
        case .commit:
            commit()
        case .cancel:
            hide()
        }
    }

    public func setSelection(_ index: Int) {
        guard isVisible, windows.indices.contains(index) else { return }
        selectedIndex = index
        onSelectionChange?(index)
    }

    private func present() {
        let snap = enumerator.snapshot()
        mru.prune(keeping: Set(snap.map { $0.id }))
        windows = mru.ordered(snap)
        guard !windows.isEmpty else { return }
        selectedIndex = windows.count > 1 ? 1 : 0
        isVisible = true
        onShow?(windows, selectedIndex)
    }

    private func advance(by delta: Int) {
        guard !windows.isEmpty else { return }
        let count = windows.count
        selectedIndex = ((selectedIndex + delta) % count + count) % count
        onSelectionChange?(selectedIndex)
    }

    private func commit() {
        guard isVisible else { return }
        let target = windows.indices.contains(selectedIndex) ? windows[selectedIndex] : nil
        hide()
        if let target {
            mru.recordFocus(target.id)
            activator.activate(target)
        }
    }

    private func hide() {
        guard isVisible else { return }
        isVisible = false
        onHide?()
    }
}
