import XCTest
import CoreGraphics
@testable import CmdTabCore

final class MRUStoreTests: XCTestCase {
    private func win(_ id: CGWindowID) -> WindowInfo {
        WindowInfo(id: id, pid: 1, appName: "App", title: "T\(id)", isMinimized: false)
    }

    func testRecordFocusMovesToFront() {
        let s = MRUStore()
        s.recordFocus(1); s.recordFocus(2); s.recordFocus(1)
        XCTAssertEqual(s.order, [1, 2])
    }

    func testOrderedSortsByMRUWithUnknownsLastPreservingInput() {
        let s = MRUStore()
        s.recordFocus(3); s.recordFocus(2)   // order = [2, 3]
        let result = s.ordered([win(1), win(2), win(3)])
        XCTAssertEqual(result.map { $0.id }, [2, 3, 1])
    }

    func testPruneRemovesAbsentIDs() {
        let s = MRUStore()
        s.recordFocus(1); s.recordFocus(2); s.recordFocus(3)
        s.prune(keeping: [2, 3])
        XCTAssertEqual(s.order, [3, 2])
    }

    func testSeedPopulatesEmptyOrder() {
        let s = MRUStore()
        s.seed([5, 4, 3])
        XCTAssertEqual(s.order, [5, 4, 3])
        // A subsequent snapshot is now ranked by the seeded z-order.
        let result = s.ordered([win(3), win(4), win(5)])
        XCTAssertEqual(result.map { $0.id }, [5, 4, 3])
    }

    func testSeedDoesNotClobberExistingOrder() {
        let s = MRUStore()
        s.recordFocus(1)
        s.seed([5, 4, 3])
        XCTAssertEqual(s.order, [1])
    }
}
