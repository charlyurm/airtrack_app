import AirTrackCore
import CoreMedia
import Foundation

struct TrackingMetrics: Equatable, Sendable {
    var cameraFPS: Double = 0
    var visionFPS: Double = 0
    /// Duration of the Vision request alone (smoothed).
    var visionProcessingMs: Double?
    /// Capture timestamp → HandState ready (waiting + Vision). Excludes display time,
    /// so it is NOT end-to-end latency.
    var captureToHandStateMs: Double?
    /// Frames replaced in the one-slot mailbox by a newer frame before Vision got to them.
    /// Expected and harmless: processing them would only add latency.
    var supersededFrames: Int = 0
    /// Frames AVFoundation itself dropped (alwaysDiscardsLateVideoFrames).
    var cameraDroppedFrames: Int = 0
}

struct TrackingResult: Sendable {
    /// Validated hands from THIS frame only, in HandOrdering order (primary first). ≤ 2.
    let hands: [HandState]
    /// Raw Vision observations this frame, before validation.
    let candidateCount: Int
    /// Why candidates were rejected this frame (false-positive diagnostics).
    let rejections: [HandRejectionReason]
    /// Cursor position posted this frame; nil when the cursor was not moved.
    let cursor: CursorUpdate?
}

/// Camera frames → Vision (own serial queue) → validated hands.
///
/// Latest-frame-wins: at most one frame is being processed and at most one waits in a
/// single-slot mailbox. A newer frame replaces the waiting one, and when Vision finishes it
/// immediately takes the newest waiting frame. Memory and latency stay bounded.
/// Cursor (PHASE 2): right after validation, on the same Vision queue, the CursorController
/// turns the primary hand into a cursor position and MacOSEventController posts it. No extra
/// queue or thread hop between hand and cursor. Only when the main actor has allowed cursor
/// control (enabled, not paused, permission granted, camera running).
/// @unchecked Sendable: `lock` guards the mailbox, counters and the cursor-allowed flag; the
/// engine, presence filter and cursor controller are confined to `visionQueue`.
final class HandTrackingPipeline: @unchecked Sendable {
    /// Called on the Vision queue for every processed frame.
    var onResult: (@Sendable (TrackingResult) -> Void)?
    /// Called on the Vision queue at most 4 times per second.
    var onMetrics: (@Sendable (TrackingMetrics) -> Void)?

    private let visionQueue = DispatchQueue(label: "com.airtrack.vision", qos: .userInteractive)
    private static let metricsInterval: TimeInterval = 0.25

    // guarded by `lock`
    private let lock = NSLock()
    private var isBusy = false
    private var pending: CameraFrame?
    private var cameraRate = FrameRateCounter()
    private var visionRate = FrameRateCounter()
    private var metrics = TrackingMetrics()
    private var lastMetricsPublish: TimeInterval = 0
    private var cursorAllowed = false

    // visionQueue only
    private let engine = VisionHandTrackingEngine()
    private var presenceFilter = HandPresenceFilter()
    private var cursorController = CursorController()
    private let events = MacOSEventController()
    private var lastHandCount = 0
    private var consecutiveErrors = 0

    /// Called on the camera's video queue.
    func submit(_ frame: CameraFrame) {
        let now = ProcessInfo.processInfo.systemUptime
        let startNow = lock.withLock { () -> Bool in
            metrics.cameraFPS = cameraRate.tick(at: now)
            guard isBusy else {
                isBusy = true
                return true
            }
            if pending != nil { metrics.supersededFrames += 1 }
            pending = frame
            return false
        }
        guard startNow else { return }
        visionQueue.async { [self] in drain(startingWith: frame) }
    }

    /// Main actor → pipeline. When false the cursor is never touched and cursor state is dropped.
    func setCursorControl(allowed: Bool) {
        let changed = lock.withLock { () -> Bool in
            defer { cursorAllowed = allowed }
            return cursorAllowed != allowed
        }
        if changed { Log.tracking.info("Cursor control \(allowed ? "active" : "inactive", privacy: .public)") }
    }

    func apply(_ settings: AirTrackSettings) {
        visionQueue.async { [self] in cursorController.apply(settings) }
    }

    func recordCameraDrop() {
        lock.withLock { metrics.cameraDroppedFrames += 1 }
    }

    /// Clears metrics, the mailbox and tracking state (camera started, switched or stopped).
    func reset() {
        lock.withLock {
            pending = nil
            cameraRate.reset()
            visionRate.reset()
            metrics = TrackingMetrics()
        }
        visionQueue.async { [self] in
            presenceFilter.reset()
            cursorController.reset()
            if lastHandCount > 0 { Log.tracking.info("Tracking reset") }
            lastHandCount = 0
            consecutiveErrors = 0
        }
    }

    private func drain(startingWith first: CameraFrame) {
        var next: CameraFrame? = first
        while let frame = next {
            process(frame)
            next = lock.withLock { () -> CameraFrame? in
                let newest = pending
                pending = nil
                if newest == nil { isBusy = false }
                return newest
            }
        }
    }

    private func process(_ frame: CameraFrame) {
        let start = ProcessInfo.processInfo.systemUptime
        var candidates: [HandState] = []
        do {
            candidates = try engine.process(frame)
            if consecutiveErrors > 0 {
                Log.vision.info("Vision recovered after \(self.consecutiveErrors) failed frames")
                consecutiveErrors = 0
            }
        } catch {
            consecutiveErrors += 1
            if consecutiveErrors == 1 {
                Log.vision.error("Vision request failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        // A failed request yields no candidates → no hands this frame. Nothing is carried over.
        let hands = presenceFilter.update(candidates: candidates)
        let end = ProcessInfo.processInfo.systemUptime
        let captureToResult = CMClockGetTime(CMClockGetHostTimeClock()).seconds - frame.timestamp

        if hands.count != lastHandCount {
            if hands.isEmpty {
                Log.tracking.info("Hand lost")
            } else {
                Log.tracking.info("Tracking \(hands.count) hand(s)")
            }
            lastHandCount = hands.count
        }
        let cursor = updateCursor(hands: hands, timestamp: frame.timestamp)
        onResult?(TrackingResult(
            hands: hands,
            candidateCount: candidates.count,
            rejections: presenceFilter.lastRejections,
            cursor: cursor
        ))

        let snapshot = lock.withLock { () -> TrackingMetrics? in
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

    /// visionQueue. Moves the system cursor only for a valid primary hand while allowed.
    private func updateCursor(hands: [HandState], timestamp: TimeInterval) -> CursorUpdate? {
        guard lock.withLock({ cursorAllowed }) else {
            cursorController.reset()
            return nil
        }
        // Only read the real cursor position when a new session starts (reacquisition).
        let reference = cursorController.needsReferencePosition ? events.currentCursorLocation() : nil
        let update = cursorController.update(
            hands: hands,
            timestamp: timestamp,
            display: events.mainDisplayBounds(),
            isActive: true,
            currentCursor: reference
        )
        if let update {
            events.moveCursor(to: update.screen)
        }
        return update
    }
}
