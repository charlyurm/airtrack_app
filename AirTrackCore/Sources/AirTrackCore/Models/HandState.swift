import Foundation

/// One tracking result for one frame.
///
/// Coordinate convention (the tracking adapter MUST convert into it):
/// - normalized 0...1 on both axes of the camera image
/// - origin at the TOP-LEFT, x grows right, y grows DOWN
/// - NOT mirrored (raw camera image); mirroring happens in `CursorMapper`
///
/// Vision reports origin bottom-left, so its adapter must use `y = 1 - y`.
public struct HandState: Equatable, Sendable {
    /// Seconds, monotonic (e.g. the capture presentation timestamp).
    public var timestamp: TimeInterval
    public var landmarks: [HandJoint: HandLandmark]
    /// Width / height of the source image. Normalized x and y units differ on
    /// non-square images, so distances must be aspect-corrected.
    public var imageAspectRatio: Double

    public init(timestamp: TimeInterval, landmarks: [HandJoint: HandLandmark] = [:], imageAspectRatio: Double = 1) {
        self.timestamp = timestamp
        self.landmarks = landmarks
        self.imageAspectRatio = imageAspectRatio
    }

    public static func untracked(at timestamp: TimeInterval) -> HandState {
        HandState(timestamp: timestamp)
    }

    public var isTracked: Bool { !landmarks.isEmpty }

    public func position(of joint: HandJoint, minimumConfidence: Double = 0) -> Point2D? {
        guard let landmark = landmarks[joint],
              landmark.confidence >= minimumConfidence,
              landmark.position.isFinite else { return nil }
        return landmark.position
    }

    /// Distance between two joints in units of image height.
    public func aspectCorrectedDistance(from a: HandJoint, to b: HandJoint, minimumConfidence: Double = 0) -> Double? {
        guard let p = position(of: a, minimumConfidence: minimumConfidence),
              let q = position(of: b, minimumConfidence: minimumConfidence) else { return nil }
        let aspect = (imageAspectRatio.isFinite && imageAspectRatio > 0) ? imageAspectRatio : 1
        let dx = (p.x - q.x) * aspect
        let dy = p.y - q.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
