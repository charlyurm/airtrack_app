import Foundation

/// User-tunable settings. Persisted by the macOS layer (UserDefaults); this type
/// only defines values, defaults and valid ranges.
public struct AirTrackSettings: Equatable, Sendable, Codable {
    // Cursor (PHASE 2). All initial values are UNCALIBRATED; tune them on the real Mac.
    /// 1 = the active area maps exactly onto the screen; >1 = less hand travel per screen.
    public var cursorSensitivity: Double = 1.0
    /// Smoothing while the finger is still or slow: EMA weight of the previous position per
    /// frame at 30 fps (0 = none, max 0.95). PHASE 2.1: time-based and reduced automatically
    /// as the finger speeds up (see `cursorSpeedResponse`, AdaptiveCursorSmoother).
    /// Phase 2 used 0.35 FIXED at every speed. With speed adaptation the rest value can be
    /// higher (the Mac test found high smoothing more natural, only its lag was the problem):
    /// 0.6 at rest ≈ 0.57 slow · 0.39 at 0.5 screens/s · 0.14 at 2.5 screens/s. UNCALIBRATED.
    public var cursorSmoothing: Double = 0.6
    /// PHASE 2.1: how much speed reduces smoothing (s per display-normalized unit). 0 = fixed
    /// smoothing (time-based Phase 2 behavior). UNCALIBRATED.
    public var cursorSpeedResponse: Double = 1.0
    /// Finger micro-movement ignored while still, in active-area units (0.003 ≈ 0.3 % of the
    /// active area ≈ 4 pt on a 1440-pt-wide screen at sensitivity 1).
    public var cursorDeadZone: Double = 0.003
    /// When the hand is (re)acquired the cursor starts where it already is and glides onto the
    /// finger's mapped position over this time instead of jumping. 0 = jump immediately.
    public var cursorReacquisitionBlend: TimeInterval = 0.2
    /// PHASE 2.1: once a full hand has been acquired, keep following its index tip through
    /// short dropouts and partial views near the frame edges (PointerTracker). Off = Phase 2
    /// behavior (only a fully valid hand moves the cursor; any gap is an immediate loss).
    public var cursorPeripheralTracking: Bool = true
    /// PHASE 3A-2: multiplier of the scroll response (content points per hand movement).
    /// Not exposed in the UI yet: defaults first, configuration after physical validation.
    public var scrollSensitivity: Double = 1.0
    /// PHASE 3A-2: two-finger / open-hand vertical scroll reaches macOS. Off = the interaction
    /// engine only observes (3A-1 shadow mode) and the cursor behaves exactly like Phase 2.1.
    public var scrollGesturesEnabled: Bool = true
    /// PHASE 3A-2: flips the sign the macOS adapter uses. The Core always means "content
    /// follows the hand"; whether synthetic events need flipping is settled on the real Mac.
    public var scrollDirectionInverted: Bool = false
    /// PHASE 3B: index + thumb pinch → left click / drag reaches macOS. Off = the pinch is only
    /// observed (shadow mode) and the cursor behaves exactly as without it. The thresholds are
    /// not user settings yet: defaults first, customization after physical validation.
    public var clickGesturesEnabled: Bool = true
    /// LEGACY Phase 0 (GestureEngine, not wired). PHASE 3B uses PoseConfiguration / Pinch*
    /// configurations in hand-scale units of the Phase 3 feature extractor instead.
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
    public static let scrollSensitivityRange: ClosedRange<Double> = 0.25...4.0

    public var sanitized: AirTrackSettings {
        var s = self
        let defaults = AirTrackSettings.default
        s.cursorSensitivity = Self.clamp(cursorSensitivity, CursorMapper.sensitivityRange, fallback: defaults.cursorSensitivity)
        s.cursorSmoothing = Self.clamp(cursorSmoothing, CursorSmoother.smoothingRange, fallback: defaults.cursorSmoothing)
        s.cursorSpeedResponse = Self.clamp(cursorSpeedResponse, AdaptiveCursorSmoother.speedResponseRange, fallback: defaults.cursorSpeedResponse)
        s.cursorDeadZone = Self.clamp(cursorDeadZone, DeadZoneFilter.thresholdRange, fallback: defaults.cursorDeadZone)
        s.cursorReacquisitionBlend = Self.clamp(cursorReacquisitionBlend, Self.reacquisitionBlendRange, fallback: defaults.cursorReacquisitionBlend)
        s.scrollSensitivity = Self.clamp(scrollSensitivity, Self.scrollSensitivityRange, fallback: defaults.scrollSensitivity)
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
