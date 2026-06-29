import CoreGraphics

public final class MRUStore {
    public private(set) var order: [CGWindowID] = []

    public init() {}

    /// Seed the MRU order, most-recent first (e.g. from window z-order at
    /// launch, where the front-most window is the most recently used). No-op
    /// once any focus has been recorded, so a real focus event never loses to
    /// a late seed.
    public func seed(_ ids: [CGWindowID]) {
        guard order.isEmpty else { return }
        order = ids
    }

    /// Move a window to the front of the MRU list.
    public func recordFocus(_ id: CGWindowID) {
        order.removeAll { $0 == id }
        order.insert(id, at: 0)
    }

    /// Order a snapshot by MRU rank; windows unknown to the store keep their
    /// input order and go last.
    public func ordered(_ windows: [WindowInfo]) -> [WindowInfo] {
        var rank: [CGWindowID: Int] = [:]
        for (i, id) in order.enumerated() { rank[id] = i }
        return windows.enumerated().sorted { lhs, rhs in
            let rl = rank[lhs.element.id] ?? Int.max
            let rr = rank[rhs.element.id] ?? Int.max
            if rl != rr { return rl < rr }
            return lhs.offset < rhs.offset
        }.map { $0.element }
    }

    /// Drop ids that are no longer present.
    public func prune(keeping present: Set<CGWindowID>) {
        order.removeAll { !present.contains($0) }
    }
}
