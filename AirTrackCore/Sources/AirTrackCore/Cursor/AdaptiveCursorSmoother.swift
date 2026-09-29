import Foundation

/// Velocity-aware, time-based low-pass filter for the cursor (PHASE 2.1).
///
/// Same family as the "1€ filter": a first-order low-pass whose time constant shrinks as the
/// estimated speed grows.
///
///     tau(v)   = restTimeConstant / (1 + speedResponse · v)
///     weight   = exp(-dt / tau(v))                      (weight of the previous output)
///     output   = previous + (input − previous) · (1 − weight)
///
/// - Still or slow finger → tau ≈ restTimeConstant → strong smoothing (stable, no jitter).
/// - Fast finger → tau shrinks → almost no smoothing (low lag). At high speed the lag
///   distance v · tau tends to restTimeConstant / speedResponse, so it is bounded.
/// - Stop → the gap closes, the speed estimate decays, full smoothing returns.
///
/// Guarantees (tested): deterministic; the output is a convex combination of the previous
/// output and the input, so on each axis it always lies between them → no overshoot and no
/// oscillation; time-based, so the same motion gives the same result at 30 or 60 fps (exactly
/// when `speedResponse` is 0).
///
/// Units: points in display-normalized space (0…1), speed in display-normalized units per
/// second, i.e. independent of the screen resolution.
///
/// `restSmoothing` keeps the Phase 2 meaning of `cursorSmoothing`: the EMA weight of the
/// previous position per frame at `referenceFrameInterval` (30 fps) while the finger is still.
/// With `speedResponse` 0 and 30 fps this filter is exactly the Phase 2 EMA.
public struct AdaptiveCursorSmoother: Sendable {
    public static let speedResponseRange: ClosedRange<Double> = 0...8
    /// Frame interval at which `restSmoothing` equals the per-frame EMA weight (30 fps).
    public static let referenceFrameInterval: TimeInterval = 1.0 / 30
    /// Longer gaps (e.g. a bridged tracking dropout) count as this long, so one step stays bounded.
    public static let maximumFrameInterval: TimeInterval = 0.25
    /// Time constant of the speed estimate. Short, so the filter reacts within ~2 frames when
    /// a fast movement starts; the dead zone keeps a still finger at exactly zero speed.
    public static let speedTimeConstant: TimeInterval = 0.05

    /// EMA weight of the previous position at rest (0 = no smoothing, max 0.95).
    public var restSmoothing: Double
    /// How strongly speed reduces smoothing, in seconds per display-normalized unit.
    /// 0 = fixed smoothing (time-based Phase 2 behavior).
    public var speedResponse: Double

    public private(set) var current: Point2D?
    /// Estimated speed of the finger in display-normalized units per second (diagnostics).
    public private(set) var speed: Double = 0
    /// Weight of the previous output used in the last step (0 = raw input). Diagnostics.
    public private(set) var lastWeight: Double = 0
    private var velocity = Point2D.zero
    private var lastTimestamp: TimeInterval?

    public init(restSmoothing: Double = 0.35, speedResponse: Double = 2) {
        self.restSmoothing = restSmoothing
        self.speedResponse = speedResponse
    }

    public var effectiveRestSmoothing: Double {
        guard restSmoothing.isFinite else { return 0 }
        return min(max(restSmoothing, CursorSmoother.smoothingRange.lowerBound), CursorSmoother.smoothingRange.upperBound)
    }

    public var effectiveSpeedResponse: Double {
        guard speedResponse.isFinite else { return 0 }
        return min(max(speedResponse, Self.speedResponseRange.lowerBound), Self.speedResponseRange.upperBound)
    }

    /// Time constant while still, equivalent to `restSmoothing` per frame at 30 fps.
    public var restTimeConstant: TimeInterval {
        let base = effectiveRestSmoothing
        guard base > 0 else { return 0 }
        return -Self.referenceFrameInterval / log(base)
    }

    /// Time constant used at `speed` (display-normalized units per second).
    public func timeConstant(atSpeed speed: Double) -> TimeInterval {
        let v = speed.isFinite ? max(speed, 0) : 0
        return restTimeConstant / (1 + effectiveSpeedResponse * v)
    }

    public mutating func smooth(_ point: Point2D, at timestamp: TimeInterval) -> Point2D {
        guard let previous = current, let lastTimestamp else {
            start(at: point, timestamp: timestamp)
            return point
        }
        let dt = timestamp - lastTimestamp
        guard dt.isFinite, dt > 0 else {
            // No elapsed time (duplicate or out-of-order timestamp): speed cannot be measured.
            // Fall back to the Phase 2 per-frame EMA with the rest smoothing.
            let weight = effectiveRestSmoothing
            let result = previous + (point - previous) * (1 - weight)
            current = result
            lastWeight = weight
            return result
        }
        let h = min(dt, Self.maximumFrameInterval)

        // Speed: distance between the new input and the previous OUTPUT, low-passed. Measuring
        // against the output keeps the filter responsive while it is behind the finger.
        let rawVelocity = (point - previous) * (1 / h)
        let speedAlpha = 1 - exp(-h / Self.speedTimeConstant)
        velocity = velocity + (rawVelocity - velocity) * speedAlpha
        speed = velocity.length

        let tau = timeConstant(atSpeed: speed)
        let weight = tau > 0 ? exp(-h / tau) : 0
        // previous + (point − previous)·(1 − weight): exactly `previous` for an unchanged input.
        let result = previous + (point - previous) * (1 - weight)
        current = result
        lastWeight = weight
        self.lastTimestamp = timestamp
        return result
    }

    /// Tracking lost / paused: never sweep from a stale position.
    public mutating func reset() {
        current = nil
        lastTimestamp = nil
        velocity = .zero
        speed = 0
        lastWeight = 0
    }

    private mutating func start(at point: Point2D, timestamp: TimeInterval) {
        current = point
        lastTimestamp = timestamp.isFinite ? timestamp : nil
        velocity = .zero
        speed = 0
        lastWeight = 0
    }
}
