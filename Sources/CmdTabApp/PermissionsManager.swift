import ApplicationServices

enum PermissionsManager {
    /// Returns whether this process is trusted for Accessibility.
    /// Pass `prompt: true` to surface the system permission dialog.
    static func isAccessibilityTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }
}
