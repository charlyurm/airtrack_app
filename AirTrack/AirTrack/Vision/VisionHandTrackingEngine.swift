import AirTrackCore
import Vision

/// CVPixelBuffer → Vision hand pose → HandState. Runs entirely on-device.
///
/// Not thread-safe: the request object is reused across frames, so call `process` from a
/// single serial queue (HandTrackingPipeline's Vision queue).
final class VisionHandTrackingEngine {
    private let request: VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 1
        return request
    }()

    /// Returns an untracked HandState when no hand is found. Never invents landmarks.
    func process(_ frame: CameraFrame) throws -> HandState {
        // Mac cameras deliver upright landscape buffers, so no orientation correction (.up).
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.pixelBuffer, orientation: .up, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first else {
            return .untracked(at: frame.timestamp)
        }
        return try HandStateMapper.handState(from: observation, frame: frame)
    }
}
