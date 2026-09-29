import AirTrackCore
import CoreMedia
import Foundation

struct TrackingMetrics: Equatable, Sendable {
    var cameraFPS: Double = 0
    var visionFPS: Double = 0
    /// Duration of the Vision request alone (smoothed).
    var visionProcessingMs: Double?
    /// Capture timestamp → HandState ready (queue wait + Vision). Excludes display time,
    /// so it is NOT end-to-end latency.
    var captureToHandStateMs: Double?
    /// Frames skipped because Vision was still busy, plus frames AVFoundation dropped.
    var droppedFrames: Int = 0
}

/// Camera frames → Vision (on its own serial queue) → HandState.
///
/// Backpressure: at most one frame is in flight. If Vision is still busy when a new frame
/// arrives, that frame is dropped instead of queued, so latency never accumulates.
/// @unchecked Sendable: `lock` guards the shared counters; the engine and tracking flags are
/// confined to `visionQueue`.
final class HandTrackingPipeline: @unchecked Sendable {
    /// Called on the Vision queue for every processed frame.
    var onHand: (@Sendable (HandState) -> Void)?
    /// Called on the Vision queue at most 4 times per second.
    var onMetrics: (@Sendable (TrackingMetrics) -> Void)?

    private let visionQueue = DispatchQueue(label: "com.airtrack.vision", qos: .userInteractive)
    private static let metricsInterval: TimeInterval = 0.25

    // guarded by `lock`
    private let lock = NSLock()
    private var isBusy = false
    private var cameraRate = FrameRateCounter()
    private var visionRate = FrameRateCounter()
    private var metrics = TrackingMetrics()
    private var lastMetricsPublish: TimeInterval = 0

    // visionQueue only
    private let engine = VisionHandTrackingEngine()
    private var wasTracked = false
    private var consecutiveErrors = 0

    /// Called on the camera's video queue.
    func submit(_ frame: CameraFrame) {
        let now = ProcessInfo.processInfo.systemUptime
        let accepted = lock.withLock { () -> Bool in
            metrics.cameraFPS = cameraRate.tick(at: now)
            if isBusy {
                metrics.droppedFrames += 1
                return false
            }
            isBusy = true
            return true
        }
        guard accepted else { return }
        visionQueue.async { [self] in process(frame) }
    }

    func recordCameraDrop() {
        lock.withLock { metrics.droppedFrames += 1 }
    }

    /// Clears metrics and tracking state (camera stopped, switched or disconnected).
    func reset() {
        lock.withLock {
            cameraRate.reset()
            visionRate.reset()
            metrics = TrackingMetrics()
        }
        visionQueue.async { [self] in
            if wasTracked { Log.tracking.info("Tracking reset") }
            wasTracked = false
            consecutiveErrors = 0
        }
    }

    private func process(_ frame: CameraFrame) {
        let start = ProcessInfo.processInfo.systemUptime
        let hand: HandState
        do {
            hand = try engine.process(frame)
            if consecutiveErrors > 0 {
                Log.vision.info("Vision recovered after \(self.consecutiveErrors) failed frames")
                consecutiveErrors = 0
            }
        } catch {
            consecutiveErrors += 1
            if consecutiveErrors == 1 {
                Log.vision.error("Vision request failed: \(error.localizedDescription, privacy: .public)")
            }
            hand = .untracked(at: frame.timestamp)
        }
        let end = ProcessInfo.processInfo.systemUptime
        let captureToResult = CMClockGetTime(CMClockGetHostTimeClock()).seconds - frame.timestamp

        if hand.isTracked != wasTracked {
            wasTracked = hand.isTracked
            if hand.isTracked {
                Log.tracking.info("Hand acquired (\(hand.landmarks.count) of \(HandJoint.allCases.count) joints)")
            } else {
                Log.tracking.info("Hand lost")
            }
        }
        onHand?(hand)

        let snapshot = lock.withLock { () -> TrackingMetrics? in
            isBusy = false
            metrics.visionFPS = visionRate.tick(at: end)
            let processingMs = (end - start) * 1000
            metrics.visionProcessingMs = metrics.visionProcessingMs.map { $0 * 0.8 + processingMs * 0.2 } ?? processingMs
            // Only trust the capture clock if the value is plausible.
            metrics.captureToHandStateMs = (0...2).contains(captureToResult) ? captureToResult * 1000 : nil
            guard end - lastMetricsPublish >= Self.metricsInterval else { return nil }
            lastMetricsPublish = end
            return metrics
        }
        if let snapshot { onMetrics?(snapshot) }
    }
}
