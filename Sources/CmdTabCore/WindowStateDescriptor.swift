import Foundation

/// Describes one window-state icon: the SF Symbol to draw, how to label it in
/// the legend, and which `WindowInfo` flag turns it on. The single source of
/// truth shared by the overlay rows and the legend window.
public struct WindowStateDescriptor {
    public let symbolName: String
    public let title: String
    public let explanation: String
    public let isActive: (WindowInfo) -> Bool

    public init(
        symbolName: String,
        title: String,
        explanation: String,
        isActive: @escaping (WindowInfo) -> Bool
    ) {
        self.symbolName = symbolName
        self.title = title
        self.explanation = explanation
        self.isActive = isActive
    }
}

/// All window-state icons, in the same left→right priority order the overlay
/// renders them in.
public let windowStateDescriptors: [WindowStateDescriptor] = [
    WindowStateDescriptor(
        symbolName: "checkmark.circle",
        title: "Current window",
        explanation: "The window you're in right now.",
        isActive: { $0.isCurrent }
    ),
    WindowStateDescriptor(
        symbolName: "exclamationmark.bubble",
        title: "Dialog",
        explanation: "A dialog or alert, not a document window.",
        isActive: { $0.isDialog }
    ),
    WindowStateDescriptor(
        symbolName: "minus.circle",
        title: "Minimized",
        explanation: "Minimized to the Dock.",
        isActive: { $0.isMinimized }
    ),
    WindowStateDescriptor(
        symbolName: "arrow.up.left.and.arrow.down.right",
        title: "Full screen",
        explanation: "In macOS full-screen mode.",
        isActive: { $0.isFullScreen }
    ),
    WindowStateDescriptor(
        symbolName: "macwindow.on.rectangle",
        title: "On another Space",
        explanation: "On another desktop; activating it switches Spaces.",
        isActive: { $0.isOnOtherSpace }
    ),
    WindowStateDescriptor(
        symbolName: "eye.slash",
        title: "Hidden",
        explanation: "Its app is hidden (⌘H).",
        isActive: { $0.isHidden }
    ),
]
