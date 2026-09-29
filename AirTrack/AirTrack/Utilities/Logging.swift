import os

/// Structured logging (Console.app → filter by subsystem "com.airtrack.AirTrack").
/// Only state changes are logged, never per-frame data or images.
enum Log {
    private static let subsystem = "com.airtrack.AirTrack"

    static let permissions = Logger(subsystem: subsystem, category: "permissions")
    static let camera = Logger(subsystem: subsystem, category: "camera")
    static let vision = Logger(subsystem: subsystem, category: "vision")
    static let tracking = Logger(subsystem: subsystem, category: "tracking")
}
