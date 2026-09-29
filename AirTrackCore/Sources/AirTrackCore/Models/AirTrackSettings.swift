import Foundation

/// User-tunable settings. Persisted by the macOS layer (UserDefaults); this type
/// only defines values, defaults and valid ranges.
public struct AirTrackSettings: Equatable, Sendable, Codable {
    // Cursor (PHASE 2). All initial values are UNCALIBRATED; tune them on the real Mac.
    /// 1 = the active area maps exactly onto the screen; >1 = less hand travel per screen.
    public var cursorSensitivity: Double = 1.0
    /// EMA weight of the previous position (0 = none, max 0.95). Kept moderate because the
    /// dead zone already handles a still finger.
    public var cursorSmoothing: Double = 0.35
    /// Finger micro-movement ignored while still, in active-area units (0.003 ≈ 0.3 % of the
    /// active area ≈ 4 pt on a 1440-pt-wide screen at sensitivity 1).
    public var cursorDeadZone: Double = 0.003
    /// When the hand is (re)acquired the cursor starts where it already is and glides onto the
    /// finger's mapped position over this time instead of jumping. 0 = jump immediately.
    public var cursorReacquisitionBlend: TimeInterval = 0.2
    /// Reserved for PHASE 4 (scroll). Not used yet.
    public var scrollSensitivity: Double = 1.0
    /// Pinch start threshold, as a ratio of hand size (see HandScale).
    /// Initial, UNCALIBRATED value — validate with the real camera.
    public var pinchThreshold: Double = 0.25
    /// Pinch release threshold, as a ratio of hand size. Must be > pinchThreshold.
    /// Initial, UNCALIBRATED value — validate with the real camera.
    public var pinchReleaseThreshold: Double = 0.35
    public var doubleClickInterval: TimeInterval = 0.4
    /// Mirror the raw camera image for the cursor so the cursor follows the user's physical
    /// left/right (the camera faces the user). This is the only cursor-side mirror.
    public var mirrorCamera: Bool = true
    /// Active area in mirrored camera space (x: xMin…xMax, y: yMin…yMax), mapped onto the screen.
    public var activeArea: Rect2D = CursorMapper.defaultActiveArea
    public var minimumLandmarkConfidence: Double = 0.3
    public var emergencyToggleShortcut: KeyboardShortcut = .defaultEmergencyToggle

    public init() {}

    public static let `default` = AirTrackSettings()

    public static let doubleClickIntervalRange: ClosedRange<TimeInterval> = 0.15...1.0
    public static let reacquisitionBlendRange: ClosedRange<TimeInterval> = 0...1.0

    public var sanitized: AirTrackSettings {
        var s = self
        let defaults = AirTrackSettings.default
        s.cursorSensitivity = Self.clamp(cursorSensitivity, CursorMapper.sensitivityRange, fallback: defaults.cursorSensitivity)
        s.cursorSmoothing = Self.clamp(cursorSmoothing, CursorSmoother.smoothingRange, fallback: defaults.cursorSmoothing)
        s.cursorDeadZone = Self.clamp(cursorDeadZone, DeadZoneFilter.thresholdRange, fallback: defaults.cursorDeadZone)
        s.cursorReacquisitionBlend = Self.clamp(cursorReacquisitionBlend, Self.reacquisitionBlendRange, fallback: defaults.cursorReacquisitionBlend)
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
