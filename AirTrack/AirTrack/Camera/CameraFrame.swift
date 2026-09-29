import CoreVideo
import Foundation

/// One captured frame on its way from AVFoundation to Vision. Never enters AirTrackCore.
///
/// @unchecked Sendable: the pixel buffer is read-only after capture and exactly one consumer
/// (the Vision queue) holds it at a time; it is released as soon as Vision finishes, so frames
/// are never stored.
struct CameraFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    /// Presentation timestamp in seconds, on the capture session's host-time clock.
    let timestamp: TimeInterval
    let width: Int
    let height: Int

    var aspectRatio: Double {
        height > 0 ? Double(width) / Double(height) : 1
    }
}
