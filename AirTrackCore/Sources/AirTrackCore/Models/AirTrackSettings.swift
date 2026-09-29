import Foundation

/// User-tunable settings. Persisted by the macOS layer (UserDefaults); this type
/// only defines values, defaults and valid ranges.
public struct AirTrackSettings: Equatable, Sendable, Codable {
    public var cursorSensitivity: Double = 1.0
    public var cursorSmoothing: Double = 0.5
    /// Reserved for PHASE 5 (scroll). Not used yet.
    public var scrollSensitivity: Double = 1.0
    /// Pinch start threshold, as a ratio of hand size (see HandScale).
    public var pinchThreshold: Double = 0.25
    /// Pinch release threshold, as a ratio of hand size. Must be > pinchThreshold.
    public var pinchReleaseThreshold: Double = 0.35
    public var doubleClickInterval: TimeInterval = 0.4
    public var mirrorCamera: Bool = true
    public var activeArea: Rect2D = CursorMapper.defaultActiveArea
    public var minimumLandmarkConfidence: Double = 0.3
    public var emergencyToggleShortcut: KeyboardShortcut = .defaultEmergencyToggle

    public init() {}

    public static let `default` = AirTrackSettings()

    public static let doubleClickIntervalRange: ClosedRange<TimeInterval> = 0.15...1.0

    public var sanitized: AirTrackSettings {
        var s = self
        let defaults = AirTrackSettings.default
        s.cursorSensitivity = Self.clamp(cursorSensitivity, CursorMapper.sensitivityRange, fallback: defaults.cursorSensitivity)
        s.cursorSmoothing = Self.clamp(cursorSmoothing, CursorSmoother.smoothingRange, fallback: defaults.cursorSmoothing)
        s.doubleClickInterval = Self.clamp(doubleClickInterval, Self.doubleClickIntervalRange, fallback: defaults.doubleClickInterval)
        if !activeArea.isValid { s.activeArea = defaults.activeArea }
        let pinch = pinchConfiguration.sanitized
        s.pinchThreshold = pinch.startRatio
        s.pinchReleaseThreshold = pinch.releaseRatio
        if !minimumLandmarkConfidence.isFinite { s.minimumLandmarkConfidence = defaults.minimumLandmarkConfidence }
        return s
    }

    public var pinchConfiguration: PinchConfiguration {
        PinchConfiguration(startRatio: pinchThreshold, releaseRatio: pinchReleaseThreshold, minimumConfidence: minimumLandmarkConfidence)
    }

    public var gestureConfiguration: GestureConfiguration {
        GestureConfiguration(doubleClickInterval: doubleClickInterval)
    }

    public var cursorMapper: CursorMapper {
        CursorMapper(mirrorHorizontally: mirrorCamera, activeArea: activeArea, sensitivity: cursorSensitivity)
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
