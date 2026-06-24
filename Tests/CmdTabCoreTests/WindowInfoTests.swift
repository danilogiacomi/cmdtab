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
}
