import Foundation

/// Hand-size normalization so gestures behave the same near and far from the camera.
///
/// Reference length: wrist → index MCP (a rigid bone segment that does not change
/// with finger pose). Known limitation: it is a 2D projection, so strong hand
/// pitch/yaw shortens it. REQUIRES MACOS to validate on real tracking data.
public enum HandScale {
    /// In image heights. Below this the hand is too small / degenerate to measure.
    public static let minimumReferenceLength = 0.02

    public static func referenceLength(of hand: HandState, minimumConfidence: Double = 0) -> Double? {
        guard let length = hand.aspectCorrectedDistance(from: .wrist, to: .indexMCP, minimumConfidence: minimumConfidence),
              length >= minimumReferenceLength else { return nil }
        return length
    }

    /// Distance between two joints expressed in hand-reference lengths.
    public static func normalizedDistance(from a: HandJoint, to b: HandJoint, in hand: HandState, minimumConfidence: Double = 0) -> Double? {
        guard let reference = referenceLength(of: hand, minimumConfidence: minimumConfidence),
              let distance = hand.aspectCorrectedDistance(from: a, to: b, minimumConfidence: minimumConfidence) else { return nil }
        return distance / reference
    }
}
