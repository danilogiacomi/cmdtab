import CoreGraphics
import Foundation

public enum CmdTabCore {
    public static let version = "0.1.0"
}

public struct WindowInfo: Equatable, Identifiable {
    public let id: CGWindowID
    public let pid: pid_t
    public let appName: String
    public let title: String
    public let isMinimized: Bool
    public let isFullScreen: Bool
    public let isHidden: Bool
    public let isOnOtherSpace: Bool
    public let isDialog: Bool
    public let isCurrent: Bool

    public init(
        id: CGWindowID,
        pid: pid_t,
        appName: String,
        title: String,
        isMinimized: Bool,
        isFullScreen: Bool = false,
        isHidden: Bool = false,
        isOnOtherSpace: Bool = false,
        isDialog: Bool = false,
        isCurrent: Bool = false
    ) {
        self.id = id
        self.pid = pid
        self.appName = appName
        self.title = title
        self.isMinimized = isMinimized
        self.isFullScreen = isFullScreen
        self.isHidden = isHidden
        self.isOnOtherSpace = isOnOtherSpace
        self.isDialog = isDialog
        self.isCurrent = isCurrent
    }

    /// What the overlay renders when the window has no title.
    public var displayTitle: String { title.isEmpty ? appName : title }
}
