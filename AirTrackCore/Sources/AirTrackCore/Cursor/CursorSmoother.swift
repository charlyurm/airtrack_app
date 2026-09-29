import Foundation

/// Exponential moving average: smoothed = previous * alpha + current * (1 - alpha).
///
/// Per-frame (not per-second): the effective lag depends on the frame rate. alpha is capped
/// below 1 so the cursor can never freeze.
///
/// PHASE 2.1: the cursor now uses AdaptiveCursorSmoother (time-based, velocity-aware), which
/// equals this filter at 30 fps with speed response 0. This fixed EMA remains for
/// GestureEngine (not wired yet) and as the reference behavior in tests.
public struct CursorSmoother: Sendable {
    public static let smoothingRange: ClosedRange<Double> = 0.0...0.95

    /// alpha: weight of the previous value. 0 = no smoothing.
    public var smoothing: Double
    public private(set) var current: Point2D?

    public init(smoothing: Double = 0.5) {
        self.smoothing = smoothing
    }

    public var effectiveSmoothing: Double {
        guard smoothing.isFinite else { return 0 }
        return min(max(smoothing, Self.smoothingRange.lowerBound), Self.smoothingRange.upperBound)
    }

    public mutating func smooth(_ point: Point2D) -> Point2D {
        guard let previous = current else {
            current = point
            return point
        }
        let alpha = effectiveSmoothing
        let result = previous * alpha + point * (1 - alpha)
        current = result
        return result
    }

    /// Call on tracking loss / pause so the cursor never sweeps from a stale position.
    public mutating func reset() {
        current = nil
    }
}
