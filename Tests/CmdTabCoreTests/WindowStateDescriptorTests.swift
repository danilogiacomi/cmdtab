import XCTest
import CoreGraphics
@testable import CmdTabCore

final class WindowStateDescriptorTests: XCTestCase {
    func testDescriptorCountAndOrder() {
        XCTAssertEqual(windowStateDescriptors.count, 6)
        XCTAssertEqual(
            windowStateDescriptors.map(\.symbolName),
            [
                "checkmark.circle",
                "exclamationmark.bubble",
                "minus.circle",
                "arrow.up.left.and.arrow.down.right",
                "macwindow.on.rectangle",
                "eye.slash",
            ]
        )
    }

    func testEachDescriptorActivatesOnlyForItsFlag() {
        let cases: [(String, WindowInfo)] = [
            ("checkmark.circle", make(isCurrent: true)),
            ("exclamationmark.bubble", make(isDialog: true)),
            ("minus.circle", make(isMinimized: true)),
            ("arrow.up.left.and.arrow.down.right", make(isFullScreen: true)),
            ("macwindow.on.rectangle", make(isOnOtherSpace: true)),
            ("eye.slash", make(isHidden: true)),
        ]
        for (symbol, window) in cases {
            let active = windowStateDescriptors.filter { $0.isActive(window) }
            XCTAssertEqual(active.count, 1, "\(symbol): expected exactly one active descriptor")
            XCTAssertEqual(active.first?.symbolName, symbol)
        }
    }

    func testNoDescriptorActivatesForPlainWindow() {
        let plain = make()
        XCTAssertTrue(windowStateDescriptors.allSatisfy { !$0.isActive(plain) })
    }

    private func make(
        isMinimized: Bool = false,
        isFullScreen: Bool = false,
        isHidden: Bool = false,
        isOnOtherSpace: Bool = false,
        isDialog: Bool = false,
        isCurrent: Bool = false
    ) -> WindowInfo {
        WindowInfo(
            id: 1, pid: 1, appName: "App", title: "T",
            isMinimized: isMinimized, isFullScreen: isFullScreen, isHidden: isHidden,
            isOnOtherSpace: isOnOtherSpace, isDialog: isDialog, isCurrent: isCurrent
        )
    }
}
