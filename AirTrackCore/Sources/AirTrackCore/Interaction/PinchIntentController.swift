import Foundation

/// Click vs drag thresholds, in hand-scale units / seconds. UNCALIBRATED (REQUIRES MACOS).
public struct PinchIntentConfiguration: Equatable, Sendable {
    /// Net hand travel while pinched that turns the pinch into a drag (≈ 1.5 cm on an adult
    /// hand). Measured on the knuckles (FeatureHistory), so the pinching motion of the fingers
    /// themselves never counts, and as NET displacement, so jitter back and forth cancels out.
    /// Below it, releasing is a click.
    public var dragDistance: Double = 0.15
    /// A pinch held longer than this without dragging is not a click when released: the
    /// intent is no longer clear (uncertain = no action).
    public var clickMaximumDuration: TimeInterval = 1.0

    public init() {}
}

/// PINCH_CONFIRMED → CLICK_PENDING / DRAG_PENDING → DRAG_ACTIVE (spec lifecycle names).
public enum PinchPhase: String, Equatable, Sendable {
    /// No pinch.
    case none
    /// Pinch pose seen, not confirmed (raw pose, or stable but not yet committed).
    case candidate
    /// Confirmed pinch, click or drag not decided yet (CLICK_PENDING / DRAG_PENDING).
    case pending
    /// Drag committed (DRAG_ACTIVE): the primary button is held while live.
    case dragging
}

/// How a pinch ended (diagnostics, and the record a future double click needs).
public enum PinchOutcome: String, Equatable, Sendable {
    /// Released in place, quickly, with fresh tracking: one left click.
    case click
    /// The drag ended (mouseUp).
    case dragEnded
    /// Ended without any action: too long, moved without a drag, tracking gap or loss,
    /// timeout, cancelled, or not live.
    case noAction
}

/// The click candidate record: what was true when the pinch was confirmed, plus what has
/// happened since. Everything needed to tell click from drag (and, later, a double click).
public struct PinchSession: Equatable, Sendable {
    public var startedAt: TimeInterval
    /// Tracking mode and index tip (raw image space) at confirmation.
    public var trackingMode: PointerTrackingMode
    public var indexTip: Point2D?
    /// Hand scale (image heights) and pinch distance (hand scales) at confirmation.
    public var scale: Double
    public var pinchDistance: Double?
    /// Net hand motion since confirmation, hand scales, user space.
    public var movement: MotionVector = .zero
    /// The drag was committed.
    public var dragging = false
    /// Output reaches macOS (decided at confirmation; switched off → shadow until released).
    public var live: Bool
    /// The primary button is down for this session (live drag, mouseDown sent).
    public var buttonDown = false
    /// Tracking had a gap (PointerTracker HOLD) while the click was pending: no click.
    public var interrupted = false
}

/// Completed click (timing kept for a future double click; not used in PHASE 3B).
public struct ClickRecord: Equatable, Sendable {
    public var time: TimeInterval
    public var duration: TimeInterval
}

/// Click / drag decision for a committed pinch. Pure and deterministic; the engine calls it
/// with the arbiter's decision each frame and posts whatever it returns.
///
/// Rules (uncertain = no action):
/// - Click: clean release (`gestureEnded`) observed with FULL tracking, no tracking gap while
///   pending, held ≤ `clickMaximumDuration`, net movement < `dragDistance`, never dragged. One
///   click per pinch: the session ends with the release.
/// - Drag: the pinch is supported this frame, FULL tracking, net movement ≥ `dragDistance` →
///   `beginDrag` (mouseDown) once. From then on the session can only end with `endDrag`
///   (mouseUp), whatever the reason (release, timeout, LOST, cancel, output off): never a click.
/// - Every `beginDrag` has exactly one `endDrag`; `endDrag` is only ever sent after `beginDrag`.
public struct PinchIntentController: Sendable {
    public var configuration: PinchIntentConfiguration
    public private(set) var session: PinchSession?
    public private(set) var lastClick: ClickRecord?
    /// Outcome of the pinch that ended most recently.
    public private(set) var lastOutcome: PinchOutcome?

    public init(configuration: PinchIntentConfiguration = PinchIntentConfiguration()) {
        self.configuration = configuration
    }

    public var phase: PinchPhase {
        guard let session else { return .none }
        return session.dragging ? .dragging : .pending
    }

    public var isButtonDown: Bool { session?.buttonDown ?? false }

    /// PINCH_CONFIRMED. Emits nothing for the new pinch: a confirmed pinch is still undecided.
    /// (The arbiter always releases a pinch before another commits; should a pressed session
    /// still exist, it is closed with its mouseUp rather than forgotten.)
    @discardableResult
    public mutating func begin(at now: TimeInterval, features: HandFeatures?, pointer: PointerObservation, live: Bool) -> [InteractionAction] {
        let closing = cancel()
        session = PinchSession(
            startedAt: now,
            trackingMode: pointer.mode,
            indexTip: pointer.indexTip,
            scale: features?.scale ?? 0,
            pinchDistance: features?.thumbIndexDistance,
            live: live
        )
        return closing
    }

    /// The pinch is still owned this frame.
    /// - Parameters:
    ///   - step: hand motion measured this frame (nil when no fresh features were recorded).
    ///   - held: the arbiter found the pinch supported this frame.
    public mutating func update(step: MotionVector?, held: Bool, availability: FeatureAvailability, now: TimeInterval) -> [InteractionAction] {
        guard var s = session else { return [] }
        if let step, step.isFinite { s.movement = MotionVector(dx: s.movement.dx + step.dx, dy: s.movement.dy + step.dy) }
        if availability == .gap || availability == .lost, !s.dragging { s.interrupted = true }
        var actions: [InteractionAction] = []
        if !s.dragging, held, availability == .available, s.movement.magnitude >= configuration.dragDistance {
            s.dragging = true
            if s.live {
                s.buttonDown = true
                actions.append(.beginDrag)
            }
        }
        session = s
        return actions
    }

    /// The arbiter released the pinch this frame.
    public mutating func release(reason: ReleaseReason, availability: FeatureAvailability, now: TimeInterval) -> [InteractionAction] {
        guard let s = session else { return [] }
        session = nil
        if s.dragging {
            lastOutcome = .dragEnded
            return s.buttonDown ? [.endDrag] : []
        }
        let duration = now - s.startedAt
        let clean = reason == .gestureEnded && availability == .available && !s.interrupted
        let quickAndStill = duration <= configuration.clickMaximumDuration && s.movement.magnitude < configuration.dragDistance
        guard clean, quickAndStill, s.live else {
            lastOutcome = .noAction
            return []
        }
        lastOutcome = .click
        lastClick = ClickRecord(time: now, duration: duration)
        return [.leftClick]
    }

    /// Output switched off (pause, cursor control, permission, click gestures disabled): a
    /// pressed button is released now; the rest of the pinch is only observed (never clicks).
    public mutating func silence() -> [InteractionAction] {
        guard var s = session, s.live else { return [] }
        let wasDown = s.buttonDown
        s.live = false
        s.buttonDown = false
        session = s
        return wasDown ? [.endDrag] : []
    }

    /// Pause, camera stopped, shutdown, reset: ends the pinch. mouseUp iff a drag is pressed.
    public mutating func cancel() -> [InteractionAction] {
        guard let s = session else { return [] }
        session = nil
        lastOutcome = s.dragging ? .dragEnded : .noAction
        return s.buttonDown ? [.endDrag] : []
    }
}
