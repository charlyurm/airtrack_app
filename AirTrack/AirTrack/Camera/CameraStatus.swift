import Foundation

enum CameraStatus: Equatable, Sendable {
    case unknown
    case permissionRequired
    /// Session configured, not running yet.
    case ready
    case running
    case stopped
    /// The selected camera went away (unplugged, Continuity Camera out of range…).
    /// Distinct from `error`: it is an expected condition, recoverable by reconnecting.
    case disconnected
    case error(String)

    var label: String {
        switch self {
        case .unknown: "UNKNOWN"
        case .permissionRequired: "PERMISSION REQUIRED"
        case .ready: "READY"
        case .running: "RUNNING"
        case .stopped: "STOPPED"
        case .disconnected: "DISCONNECTED"
        case .error: "ERROR"
        }
    }
}
