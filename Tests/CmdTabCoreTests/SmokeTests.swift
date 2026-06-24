import XCTest
@testable import CmdTabCore

final class SmokeTests: XCTestCase {
    func testVersionIsSet() {
        XCTAssertEqual(CmdTabCore.version, "0.1.0")
    }
}
