import Foundation

/// Converts landmarks from tracking providers that report normalized image coordinates with the
/// origin at the BOTTOM-left and y growing up (e.g. Apple Vision) into HandState's convention:
/// origin TOP-left, y down, unmirrored.
///
/// Pure coordinate logic; the provider's own types stay in the macOS layer.
public enum LandmarkCoordinateConversion {
    public struct BottomLeftLandmark: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var confidence: Double

        public init(x: Double, y: Double, confidence: Double) {
            self.x = x
            self.y = y
            self.confidence = confidence
        }
    }

    /// Joints with confidence ≤ 0 (providers report undetected joints that way) or non-finite
    /// values are dropped. No joints left → an untracked HandState. x is never mirrored here.
    public static func handState(
        fromBottomLeftOrigin points: [HandJoint: BottomLeftLandmark],
        timestamp: TimeInterval,
        imageAspectRatio: Double,
        chirality: HandChirality = .unknown,
        confidence: Double = 1
    ) -> HandState {
        var landmarks: [HandJoint: HandLandmark] = [:]
        for (joint, point) in points
        where point.confidence > 0 && point.confidence.isFinite && point.x.isFinite && point.y.isFinite {
            landmarks[joint] = HandLandmark(Point2D(x: point.x, y: 1 - point.y), confidence: point.confidence)
        }
        return HandState(
            timestamp: timestamp,
            landmarks: landmarks,
            imageAspectRatio: imageAspectRatio,
            chirality: chirality,
            confidence: confidence
        )
    }
}
