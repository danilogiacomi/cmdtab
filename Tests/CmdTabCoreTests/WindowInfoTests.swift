import XCTest
import CoreGraphics
@testable import CmdTabCore

final class WindowInfoTests: XCTestCase {
    func testEquality() {
        let a = WindowInfo(id: 1, pid: 10, appName: "Safari", title: "Inbox", isMinimized: false)
        let b = WindowInfo(id: 1, pid: 10, appName: "Safari", title: "Inbox", isMinimized: false)
        let c = WindowInfo(id: 2, pid: 10, appName: "Safari", title: "Inbox", isMinimized: false)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testStateFlagsDefaultFalseAndStore() {
        let plain = WindowInfo(id: 1, pid: 10, appName: "Safari", title: "Inbox", isMinimized: false)
        XCTAssertFalse(plain.isFullScreen)
        XCTAssertFalse(plain.isHidden)

        let flagged = WindowInfo(
            id: 2, pid: 10, appName: "Safari", title: "Inbox",
            isMinimized: true, isFullScreen: true, isHidden: true
        )
        XCTAssertTrue(flagged.isMinimized)
        XCTAssertTrue(flagged.isFullScreen)
        XCTAssertTrue(flagged.isHidden)
        XCTAssertNotEqual(plain, flagged)
    }
}
