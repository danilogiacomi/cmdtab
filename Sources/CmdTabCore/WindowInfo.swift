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

    public init(id: CGWindowID, pid: pid_t, appName: String, title: String, isMinimized: Bool) {
        self.id = id
        self.pid = pid
        self.appName = appName
        self.title = title
        self.isMinimized = isMinimized
    }

    /// What the overlay renders when the window has no title.
    public var displayTitle: String { title.isEmpty ? appName : title }
}
