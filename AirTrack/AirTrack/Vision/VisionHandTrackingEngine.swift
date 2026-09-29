import AirTrackCore
import Vision

/// CVPixelBuffer → Vision hand pose → raw hand candidates. Runs entirely on-device.
///
/// Returns every observation Vision produced (up to two); validation, ordering and the
/// tracking gate live in AirTrackCore's HandPresenceFilter. Never invents landmarks.
///
/// Not thread-safe: the request object is reused across frames, so call `process` from a
/// single serial queue (HandTrackingPipeline's Vision queue).
final class VisionHandTrackingEngine {
    static let maximumHandCount = 2

    private let request: VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = VisionHandTrackingEngine.maximumHandCount
        return request
    }()

    init() {
        if !HandStateMapper.mappingIsOneToOne {
            Log.vision.fault("Vision joint mapping is not one-to-one")
        }
        assert(HandStateMapper.mappingIsOneToOne, "Two HandJoints map to the same Vision joint")
    }

    /// Candidates in Vision's (arbitrary) order. An observation whose points cannot be read is
    /// skipped rather than turned into a hand.
    func process(_ frame: CameraFrame) throws -> [HandState] {
        // Mac cameras deliver upright landscape buffers, so no orientation correction (.up).
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.pixelBuffer, orientation: .up, options: [:])
        try handler.perform([request])
        return (request.results ?? []).compactMap { observation in
            try? HandStateMapper.handState(from: observation, frame: frame)
        }
    }
}
