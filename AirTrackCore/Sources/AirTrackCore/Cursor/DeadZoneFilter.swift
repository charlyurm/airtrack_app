import Foundation

/// Suppresses micro-movements of a finger that is meant to be still.
///
/// Holds an anchor. While the input stays within `threshold` of the anchor (distance ≤
/// threshold) the output is the anchor, so the cursor does not shiver. A larger movement
/// passes through unchanged and becomes the new anchor: no lag and no constant offset while
/// moving; at most a single step of `threshold` when motion starts.
/// Units are whatever space the points live in (CursorController: active-area units).
public struct DeadZoneFilter: Sendable {
    public static let thresholdRange: ClosedRange<Double> = 0...0.05

    public var threshold: Double
    public private(set) var anchor: Point2D?

    public init(threshold: Double) {
        self.threshold = threshold
    }

    public var effectiveThreshold: Double {
        guard threshold.isFinite else { return 0 }
        return min(max(threshold, Self.thresholdRange.lowerBound), Self.thresholdRange.upperBound)
    }

    public mutating func apply(_ point: Point2D) -> Point2D {
        guard let anchor else {
            self.anchor = point
            return point
        }
        if point.distance(to: anchor) <= effectiveThreshold {
            return anchor
        }
        self.anchor = point
        return point
    }

    public mutating func reset() {
        anchor = nil
    }
}
