import AppKit
import CoreGraphics

/// Permission to post input events (moving the cursor). macOS lists it under
/// System Settings → Privacy & Security → Accessibility.
enum AccessibilityPermissionManager {
    /// Cheap check, no UI.
    static var isGranted: Bool {
        CGPreflightPostEventAccess()
    }

    /// Asks macOS to show its prompt and add AirTrack to the Accessibility list. The app cannot
    /// grant itself the permission; the user must switch it on. Call only from an explicit user
    /// action — never in a loop.
    @discardableResult
    static func request() -> Bool {
        let granted = CGRequestPostEventAccess()
        Log.permissions.info("Accessibility request finished: \(granted ? "granted" : "not granted", privacy: .public)")
        return granted
    }

    @MainActor
    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
