import XCTest
import CoreGraphics
@testable import CmdTabCore

private final class FakeEnumerator: WindowEnumerating {
    var windows: [WindowInfo]
    init(_ w: [WindowInfo]) { windows = w }
    func snapshot() -> [WindowInfo] { windows }
}

private final class FakeActivator: WindowActivating {
    var activated: [WindowInfo] = []
    func activate(_ window: WindowInfo) { activated.append(window) }
}

final class SwitcherControllerTests: XCTestCase {
    private func win(_ id: CGWindowID) -> WindowInfo {
        WindowInfo(id: id, pid: 1, appName: "App", title: "T\(id)", isMinimized: false)
    }

    private func makeController(_ ids: [CGWindowID]) -> (SwitcherController, FakeActivator) {
        let enumerator = FakeEnumerator(ids.map(win))
        let activator = FakeActivator()
        let controller = SwitcherController(enumerator: enumerator, activator: activator, mru: MRUStore())
        return (controller, activator)
    }

    func testShowStartsOnPreviousWindow() {
        let (c, _) = makeController([1, 2, 3])
        c.handle(.show)
        XCTAssertTrue(c.isVisible)
        XCTAssertEqual(c.windows.count, 3)
        XCTAssertEqual(c.selectedIndex, 1) // previous window, not current
    }

    func testShowWithSingleWindowSelectsZero() {
        let (c, _) = makeController([1])
        c.handle(.show)
        XCTAssertEqual(c.selectedIndex, 0)
    }

    func testShowWithNoWindowsStaysHidden() {
        let (c, _) = makeController([])
        c.handle(.show)
        XCTAssertFalse(c.isVisible)
    }

    func testNextWrapsAround() {
        let (c, _) = makeController([1, 2, 3])
        c.handle(.show)            // index 1
        c.handle(.next)            // index 2
        c.handle(.next)            // wraps to 0
        XCTAssertEqual(c.selectedIndex, 0)
    }

    func testPreviousWrapsBackward() {
        let (c, _) = makeController([1, 2, 3])
        c.handle(.show)            // index 1
        c.handle(.previous)        // index 0
        c.handle(.previous)        // wraps to 2
        XCTAssertEqual(c.selectedIndex, 2)
    }

    func testSecondShowWhileVisibleAdvances() {
        let (c, _) = makeController([1, 2, 3])
        c.handle(.show)            // index 1
        c.handle(.show)            // treated as next -> index 2
        XCTAssertEqual(c.selectedIndex, 2)
    }

    func testCommitActivatesSelectedAndHides() {
        let (c, activator) = makeController([1, 2, 3])
        c.handle(.show)            // index 1 -> window id 2
        c.handle(.commit)
        XCTAssertFalse(c.isVisible)
        XCTAssertEqual(activator.activated.map { $0.id }, [2])
    }

    func testCancelHidesWithoutActivating() {
        let (c, activator) = makeController([1, 2, 3])
        c.handle(.show)
        c.handle(.cancel)
        XCTAssertFalse(c.isVisible)
        XCTAssertTrue(activator.activated.isEmpty)
    }

    func testCommandsIgnoredWhenHidden() {
        let (c, activator) = makeController([1, 2, 3])
        c.handle(.next)
        c.handle(.commit)
        XCTAssertFalse(c.isVisible)
        XCTAssertTrue(activator.activated.isEmpty)
    }

    func testSetSelectionFromHover() {
        let (c, _) = makeController([1, 2, 3])
        c.handle(.show)
        c.setSelection(2)
        XCTAssertEqual(c.selectedIndex, 2)
    }

    func testOnShowFiresWithWindowsAndSelection() {
        let (c, _) = makeController([1, 2, 3])
        var capturedWindows: [WindowInfo]?
        var capturedIndex: Int?
        c.onShow = { windows, index in
            capturedWindows = windows
            capturedIndex = index
        }
        c.handle(.show)
        XCTAssertEqual(capturedWindows?.count, 3)
        XCTAssertEqual(capturedIndex, 1)
        XCTAssertEqual(c.windows[1].id, 2)
    }

    func testOnSelectionChangeFiresOnNext() {
        let (c, _) = makeController([1, 2, 3])
        var capturedIndex: Int?
        c.onSelectionChange = { index in
            capturedIndex = index
        }
        c.handle(.show)
        c.handle(.next)
        XCTAssertEqual(capturedIndex, 2)
    }

    func testOnHideFiresOnCommit() {
        let (c, _) = makeController([1, 2, 3])
        var hideFired = false
        c.onHide = {
            hideFired = true
        }
        c.handle(.show)
        c.handle(.commit)
        XCTAssertTrue(hideFired)
    }

    func testOnHideFiresOnCancel() {
        let (c, _) = makeController([1, 2, 3])
        var hideFired = false
        c.onHide = {
            hideFired = true
        }
        c.handle(.show)
        c.handle(.cancel)
        XCTAssertTrue(hideFired)
    }
}
