import Foundation

/// Whether the index finger may move the system cursor right now.
public enum CursorControlState: Equatable, Sendable {
    /// The user has not turned cursor control on. Default: a detected hand never starts
    /// moving the cursor by itself.
    case off
    case paused
    /// Turned on, but the system permission to post input events is missing.
    case waitingForPermission
    /// Turned on and allowed, but there is no valid primary hand (or the camera is not running).
    case waitingForHand
    case active

    public static func resolve(enabled: Bool, paused: Bool, permissionGranted: Bool, handAvailable: Bool) -> CursorControlState {
        if !enabled { return .off }
        if paused { return .paused }
        if !permissionGranted { return .waitingForPermission }
        if !handAvailable { return .waitingForHand }
        return .active
    }

    public var movesCursor: Bool { self == .active }
}

public struct CursorUpdate: Equatable, Sendable {
    /// Final cursor position, normalized to the display (0…1, top-left, y down).
    public var normalized: Point2D
    /// Final cursor position in the display's coordinate space (points, not pixels).
    public var screen: Point2D
    /// Where the finger points before smoothing and reacquisition blending (diagnostics).
    public var target: Point2D
}

/// HandState → cursor position. Pure: knows nothing about cameras, Vision or macOS.
///
/// Per frame: primary hand (first of the already validated, HandOrdering-sorted hands) →
/// indexTip → active area → dead zone → sensitivity → smoothing → reacquisition blend →
/// ScreenMapper. Smoothing runs on display-normalized positions; ScreenMapper is affine, so
/// this equals smoothing in screen space (up to the edge clamp).
///
/// Safety: any frame without a usable primary index tip, or with control inactive, returns
/// nil (the caller must not move the cursor) and drops all history, so stale positions are
/// never reused. The next valid frame starts a new session anchored at `currentCursor`.
public struct CursorController: Sendable {
    public private(set) var settings: AirTrackSettings
    private var mapper: CursorMapper
    private var deadZone: DeadZoneFilter
    private var smoother: CursorSmoother
    private var blend: Blend?
    public private(set) var isTracking = false

    private struct Blend: Sendable {
        var offset: Point2D
        var startedAt: TimeInterval
    }

    public init(settings: AirTrackSettings = .default) {
        let s = settings.sanitized
        self.settings = s
        self.mapper = s.cursorMapper
        self.deadZone = DeadZoneFilter(threshold: s.cursorDeadZone)
        self.smoother = CursorSmoother(smoothing: s.cursorSmoothing)
    }

    /// True when the next valid frame starts a new session, i.e. the caller should pass the
    /// current system cursor position as `currentCursor`.
    public var needsReferencePosition: Bool { !isTracking }

    public mutating func apply(_ settings: AirTrackSettings) {
        let s = settings.sanitized
        self.settings = s
        mapper = s.cursorMapper
        deadZone.threshold = s.cursorDeadZone
        smoother.smoothing = s.cursorSmoothing
    }

    /// - Parameters:
    ///   - hands: validated hands of ONE frame, primary first (HandPresenceFilter output).
    ///   - display: target display rect in its coordinate space (points).
    ///   - isActive: CursorControlState.movesCursor.
    ///   - currentCursor: current system cursor position in `display`'s space; used only when a
    ///     new session starts, so the cursor does not jump.
    /// - Returns: the new cursor position, or nil when the cursor must not be moved.
    public mutating func update(
        hands: [HandState],
        timestamp: TimeInterval,
        display: Rect2D,
        isActive: Bool,
        currentCursor: Point2D? = nil
    ) -> CursorUpdate? {
        guard isActive,
              display.isValid,
              let hand = hands.first,
              let tip = hand.position(of: .indexTip, minimumConfidence: settings.minimumLandmarkConfidence),
              let inArea = mapper.normalizedInActiveArea(tip)
        else {
            reset()
            return nil
        }

        let stable = deadZone.apply(inArea)
        let target = mapper.applyingSensitivity(stable)
        var position = smoother.smooth(target)

        if !isTracking {
            isTracking = true
            if settings.cursorReacquisitionBlend > 0,
               let currentCursor, currentCursor.isFinite {
                let start = Rect2D.unit.clamp(display.normalizedPosition(of: currentCursor))
                blend = Blend(offset: start - position, startedAt: timestamp)
            }
        }

        if let active = blend {
            let remaining = 1 - (timestamp - active.startedAt) / settings.cursorReacquisitionBlend
            if remaining > 0 {
                position = Rect2D.unit.clamp(position + active.offset * min(remaining, 1))
            } else {
                blend = nil
            }
        }

        guard let screen = ScreenMapper.map(position, to: display) else {
            reset()
            return nil
        }
        return CursorUpdate(normalized: position, screen: screen, target: target)
    }

    /// Forget everything about the previous session (tracking lost, disabled, paused…).
    public mutating func reset() {
        isTracking = false
        blend = nil
        deadZone.reset()
        smoother.reset()
    }
}
