import Foundation

public enum SwitcherCommand: Equatable {
    case show          // ⌘ held, first Tab
    case next          // advance selection
    case previous      // ⌘+Shift+Tab
    case moveLeft, moveRight, moveUp, moveDown
    case commit        // ⌘ released
    case cancel        // Esc
}

public protocol WindowEnumerating {
    func snapshot() -> [WindowInfo]
}

public protocol WindowActivating {
    func activate(_ window: WindowInfo)
}

public protocol HotkeyMonitoring: AnyObject {
    var onCommand: ((SwitcherCommand) -> Void)? { get set }
    func start() throws
    func stop()
}
