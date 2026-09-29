import AirTrackCore
import Vision

/// VNHumanHandPoseObservation → AirTrackCore.HandState.
///
/// Identity: every AirTrack joint is looked up by its Vision joint IDENTIFIER (dictionary key
/// from `recognizedPoints(.all)`), never by position in any array. The switch below is
/// exhaustive, so adding a HandJoint without a Vision mapping is a compile error.
///
/// Coordinates: Vision reports each joint normalized to the image with the origin at the
/// BOTTOM-left (y up), on the unmirrored buffer. The flip to HandState's top-left convention
/// happens in exactly one place, AirTrackCore's LandmarkCoordinateConversion (tested there).
enum HandStateMapper {
    static func visionJointName(for joint: HandJoint) -> VNHumanHandPoseObservation.JointName {
        switch joint {
        case .wrist: .wrist
        case .thumbCMC: .thumbCMC
        case .thumbMP: .thumbMP
        case .thumbIP: .thumbIP
        case .thumbTip: .thumbTip
        case .indexMCP: .indexMCP
        case .indexPIP: .indexPIP
        case .indexDIP: .indexDIP
        case .indexTip: .indexTip
        case .middleMCP: .middleMCP
        case .middlePIP: .middlePIP
        case .middleDIP: .middleDIP
        case .middleTip: .middleTip
        case .ringMCP: .ringMCP
        case .ringPIP: .ringPIP
        case .ringDIP: .ringDIP
        case .ringTip: .ringTip
        case .pinkyMCP: .littleMCP
        case .pinkyPIP: .littlePIP
        case .pinkyDIP: .littleDIP
        case .pinkyTip: .littleTip
        }
    }

    /// True when no two AirTrack joints share a Vision identifier (checked at engine start).
    static var mappingIsOneToOne: Bool {
        Set(HandJoint.allCases.map { visionJointName(for: $0).rawValue }).count == HandJoint.allCases.count
    }

    static func handState(from observation: VNHumanHandPoseObservation, frame: CameraFrame) throws -> HandState {
        let recognized = try observation.recognizedPoints(.all)
        var points: [HandJoint: LandmarkCoordinateConversion.BottomLeftLandmark] = [:]
        for joint in HandJoint.allCases {
            guard let point = recognized[visionJointName(for: joint)] else { continue }
            points[joint] = .init(
                x: Double(point.location.x),
                y: Double(point.location.y),
                confidence: Double(point.confidence)
            )
        }
        return LandmarkCoordinateConversion.handState(
            fromBottomLeftOrigin: points,
            timestamp: frame.timestamp,
            imageAspectRatio: frame.aspectRatio,
            chirality: chirality(of: observation),
            confidence: Double(observation.confidence)
        )
    }

    private static func chirality(of observation: VNHumanHandPoseObservation) -> HandChirality {
        switch observation.chirality {
        case .left: .left
        case .right: .right
        case .unknown: .unknown
        @unknown default: .unknown
        }
    }
}
