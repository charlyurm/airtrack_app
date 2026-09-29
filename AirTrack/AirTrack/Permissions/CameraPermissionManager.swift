import AppKit
import AVFoundation

enum CameraPermission: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

enum CameraPermissionManager {
    static var current: CameraPermission {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .denied
        }
    }

    /// Shows the system prompt only when the status is `.notDetermined`; otherwise returns
    /// the stored decision immediately.
    static func request() async -> CameraPermission {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        Log.permissions.info("Camera permission request finished: \(granted ? "granted" : "not granted", privacy: .public)")
        return current
    }

    @MainActor
    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else { return }
        NSWorkspace.shared.open(url)
    }
}
