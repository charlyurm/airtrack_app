import Foundation

/// Deterministic order for several hands in one frame, independent of the provider's result order.
///
/// Rule: left to right in the RAW (unmirrored) camera image by wrist x (in a mirrored preview
/// that reads right to left). Hands without a wrist use the mean of their joints. Ties: higher
/// in the image first (smaller y), then chirality. The first hand is the primary hand.
/// Untracked hands (no landmarks) are dropped.
public enum HandOrdering {
    public static func ordered(_ hands: [HandState]) -> [HandState] {
        hands
            .compactMap { hand in anchor(of: hand).map { (hand, $0) } }
            .sorted { lhs, rhs in
                if lhs.1.x != rhs.1.x { return lhs.1.x < rhs.1.x }
                if lhs.1.y != rhs.1.y { return lhs.1.y < rhs.1.y }
                return lhs.0.chirality.rawValue < rhs.0.chirality.rawValue
            }
            .map(\.0)
    }

    /// Wrist if available, otherwise the centroid of all joints.
    public static func anchor(of hand: HandState) -> Point2D? {
        if let wrist = hand.position(of: .wrist) { return wrist }
        let points = hand.landmarks.values.map(\.position).filter(\.isFinite)
        guard !points.isEmpty else { return nil }
        let sum = points.reduce(Point2D.zero, +)
        return sum * (1 / Double(points.count))
    }
}
