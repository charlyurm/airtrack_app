import AirTrackCore
import CoreGraphics
import Vision

/// Vision observation → AirTrackCore.HandState.
///
/// Vision reports each joint normalized to the image with the origin at the BOTTOM-left
/// (y up), on the unmirrored buffer. HandState uses origin TOP-left (y down), unmirrored.
/// The flip itself is pure logic tested in AirTrackCore (LandmarkCoordinateConversion);
/// this type only extracts Vision's values.
enum HandStateMapper {
    // Computed (not a stored static) so Swift 6 does not require JointName to be Sendable.
    static var jointNames: [(HandJoint, VNHumanHandPoseObservation.JointName)] { [
        (.wrist, .wrist),
        (.thumbTip, .thumbTip),
        (.indexMCP, .indexMCP),
        (.indexPIP, .indexPIP),
        (.indexDIP, .indexDIP),
        (.indexTip, .indexTip),
        (.middleTip, .middleTip),
        (.ringTip, .ringTip),
        (.pinkyTip, .littleTip),
    ] }

    static func handState(from observation: VNHumanHandPoseObservation, frame: CameraFrame) throws -> HandState {
        let recognized = try observation.recognizedPoints(.all)
        var points: [HandJoint: LandmarkCoordinateConversion.BottomLeftLandmark] = [:]
        for (joint, name) in jointNames {
            guard let point = recognized[name] else { continue }
            points[joint] = .init(
                x: Double(point.location.x),
                y: Double(point.location.y),
                confidence: Double(point.confidence)
            )
        }
        return LandmarkCoordinateConversion.handState(
            fromBottomLeftOrigin: points,
            timestamp: frame.timestamp,
            imageAspectRatio: frame.aspectRatio
        )
    }
}
