import Foundation

/// Scroll response and inertia. Values are UNCALIBRATED starting points (REQUIRES MACOS).
/// Hand motion is in hand scales (≈ palm length), so the same physical movement scrolls the
/// same amount near or far from the camera.
public struct ScrollConfiguration: Equatable, Sendable {
    /// Content points per hand scale of movement, at slow speed and sensitivity 1.
    public var pointsPerScale: Double = 250
    /// Extra gain per hand-scale/s of speed: faster movement scrolls proportionally more.
    public var acceleration: Double = 0.5
    /// Soft deadband: this much speed (hand scales/s) is subtracted, so a hand that is
    /// almost still gives exactly 0 and slow movement still scrolls, smoothly from 0.
    public var deadbandSpeed: Double = 0.15
    /// Time constant of the speed estimate. Short on purpose: scroll must feel immediate.
    public var velocitySmoothing: TimeInterval = 0.04
    /// Upper bound of the direct scroll speed, in points per second.
    public var maximumSpeed: Double = 5000
    /// Inertia starts only above this release speed (points/s)…
    public var inertiaMinimumSpeed: Double = 250
    /// …is clamped to this…
    public var inertiaMaximumSpeed: Double = 2500
    /// …decays exponentially with this time constant…
    public var inertiaDecay: TimeInterval = 0.3
    /// …and stops below this speed or after this long, whichever comes first.
    public var inertiaStopSpeed: Double = 30
    public var inertiaMaximumDuration: TimeInterval = 1.0
    /// Longest frame interval used for one step (a longer gap is not extrapolated).
    public var maximumStep: TimeInterval = 0.25

    public init() {}

    /// Largest distance any inertia can travel: v0 · decay (bounded, test-checked).
    public var inertiaDistanceBound: Double { inertiaMaximumSpeed * inertiaDecay }
}

/// Turns vertical hand motion into scroll steps, with bounded inertia after release.
///
/// - Only the vertical component is used: once a scroll is committed its axis is locked.
/// - Output is whole points; the fraction is carried, so 0.4 + 0.4 + 0.4 → 1.
/// - Inertia begins only when the gesture ENDS with enough speed. A hand that stops while
///   still holding the pose simply stops scrolling.
/// - Deterministic: driven by frame timestamps, no clock, no timers.
public struct ScrollController: Sendable {
    public enum State: String, Equatable, Sendable {
        case idle
        case scrolling
        case momentum
    }

    public var configuration: ScrollConfiguration
    /// User multiplier (AirTrackSettings.scrollSensitivity, sanitized).
    public var sensitivity: Double = 1

    public private(set) var state: State = .idle
    /// Hand speed (hand scales/s, + = down) after the light smoothing.
    public private(set) var handVelocity: Double = 0
    /// Content speed of the last step, points/s (+ = content moves down).
    public private(set) var pointsPerSecond: Double = 0
    public private(set) var lastDelta: Int = 0
    private var remainder: Double = 0
    private var momentumStart: TimeInterval = 0
    private var momentumSpeed: Double = 0
    private var momentumLast: TimeInterval = 0
    private var momentumEmitted = false

    public init(configuration: ScrollConfiguration = ScrollConfiguration()) {
        self.configuration = configuration
    }

    /// Content speed (points/s) for a hand speed (hand scales/s), with deadband and gain.
    public func contentSpeed(forHandSpeed v: Double) -> Double {
        guard v.isFinite else { return 0 }
        let effective = max(0, abs(v) - configuration.deadbandSpeed)
        guard effective > 0 else { return 0 }
        let gain = configuration.pointsPerScale * max(0, sensitivity.isFinite ? sensitivity : 1)
        let speed = min(gain * effective * (1 + configuration.acceleration * effective), configuration.maximumSpeed)
        return v < 0 ? -speed : speed
    }

    /// Scroll committed. `step` is this frame's vertical hand motion (hand scales) and its dt.
    public mutating func begin(step: (dy: Double, dt: TimeInterval)?) -> ScrollAction {
        state = .scrolling
        remainder = 0
        momentumEmitted = false
        handVelocity = 0
        if let step, step.dt > 0, step.dy.isFinite {
            handVelocity = step.dy / step.dt
        }
        let delta = emit(dt: step?.dt ?? 0)
        return ScrollAction(delta: delta, phase: .began)
    }

    /// One held frame of an active scroll. nil when nothing whole moved this frame.
    public mutating func update(dy: Double, dt: TimeInterval) -> ScrollAction? {
        guard state == .scrolling, dt > 0, dy.isFinite else { return nil }
        let raw = dy / dt
        let alpha = configuration.velocitySmoothing > 0 ? 1 - exp(-dt / configuration.velocitySmoothing) : 1
        handVelocity += (raw - handVelocity) * alpha
        let delta = emit(dt: dt)
        return delta == 0 ? nil : ScrollAction(delta: delta, phase: .changed)
    }

    /// Gesture ended. Emits `ended`; inertia follows on the next ticks when allowed and fast
    /// enough. Returns [] if no scroll was active.
    public mutating func end(allowMomentum: Bool, at time: TimeInterval) -> [ScrollAction] {
        guard state == .scrolling else { return [] }
        let releaseSpeed = pointsPerSecond
        lastDelta = 0
        if allowMomentum, abs(releaseSpeed) >= configuration.inertiaMinimumSpeed {
            state = .momentum
            momentumSpeed = min(abs(releaseSpeed), configuration.inertiaMaximumSpeed) * (releaseSpeed < 0 ? -1 : 1)
            momentumStart = time
            momentumLast = time
            momentumEmitted = false
            remainder = 0
        } else {
            stop()
        }
        return [ScrollAction(delta: 0, phase: .ended)]
    }

    /// Advances inertia to `time`. nil when not in momentum or nothing whole moved.
    public mutating func tick(at time: TimeInterval) -> ScrollAction? {
        guard state == .momentum, time.isFinite, time > momentumLast else { return nil }
        let c = configuration
        let from = momentumLast - momentumStart
        let to = min(time - momentumStart, from + c.maximumStep)
        momentumLast = time
        let decay = max(c.inertiaDecay, 1e-6)
        // Exact integral of v0·e^(−t/τ) between the two instants: frame-rate independent.
        let distance = momentumSpeed * decay * (exp(-from / decay) - exp(-to / decay))
        let speedNow = abs(momentumSpeed) * exp(-to / decay)
        pointsPerSecond = momentumSpeed * exp(-to / decay)
        if speedNow < c.inertiaStopSpeed || to >= c.inertiaMaximumDuration {
            let emitted = momentumEmitted
            stop()
            // A momentum that never produced a step ends silently (no dangling phase).
            return emitted ? ScrollAction(delta: 0, phase: nil, momentum: .ended) : nil
        }
        let total = remainder + distance
        let delta = Int(total.rounded(.towardZero))
        remainder = total - Double(delta)
        lastDelta = delta
        let phase: MomentumPhase = momentumEmitted ? .changed : .began
        guard delta != 0 || !momentumEmitted else { return nil }
        momentumEmitted = true
        return ScrollAction(delta: delta, phase: nil, momentum: phase)
    }

    /// Stops inertia (a new interaction started). Emits the momentum end if it had begun.
    public mutating func cancelMomentum() -> [ScrollAction] {
        guard state == .momentum else { return [] }
        let emitted = momentumEmitted
        stop()
        return emitted ? [ScrollAction(delta: 0, phase: nil, momentum: .ended)] : []
    }

    /// Terminates everything immediately (pause, permission, camera, shutdown, output off).
    /// Always closes an open phase so no app is left mid-scroll.
    public mutating func cancel() -> [ScrollAction] {
        switch state {
        case .idle:
            return []
        case .scrolling:
            stop()
            return [ScrollAction(delta: 0, phase: .ended)]
        case .momentum:
            return cancelMomentum()
        }
    }

    private mutating func emit(dt: TimeInterval) -> Int {
        let step = min(max(dt, 0), configuration.maximumStep)
        pointsPerSecond = contentSpeed(forHandSpeed: handVelocity)
        let total = remainder + pointsPerSecond * step
        let delta = Int(total.rounded(.towardZero))
        remainder = total - Double(delta)
        lastDelta = delta
        return delta
    }

    private mutating func stop() {
        state = .idle
        remainder = 0
        momentumSpeed = 0
        momentumEmitted = false
        pointsPerSecond = 0
        handVelocity = 0
        lastDelta = 0
    }
}
