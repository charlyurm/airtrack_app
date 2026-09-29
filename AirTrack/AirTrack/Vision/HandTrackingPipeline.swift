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
    /// PHASE 2.1: which index tip (if any) may drive the cursor this frame and how it was
    /// obtained (full / partial / index continuity / holding / lost).
    let pointer: PointerObservation
    /// Width / height of the processed frame (positions the pointer marker in the preview).
    let imageAspectRatio: Double
    /// PHASE 3A: interaction layer output (pose, candidate, intent, lifecycle, cursor policy).
    let interaction: InteractionFrame
    /// Cursor position posted this frame (also the drag position); nil when not moved.
    let cursor: CursorUpdate?
    /// PHASE 3B: the primary button is down (live drag), per the pipeline's ledger.
    let primaryButtonDown: Bool
}

/// Camera frames → Vision (own serial queue) → validated hands.
///
/// Latest-frame-wins: at most one frame is being processed and at most one waits in a
/// single-slot mailbox. A newer frame replaces the waiting one, and when Vision finishes it
/// immediately takes the newest waiting frame. Memory and latency stay bounded.
/// Cursor (PHASE 2): right after validation, on the same Vision queue, the CursorController
/// turns the pointer into a cursor position and MacOSEventController posts it. No extra
/// queue or thread hop between hand and cursor. Only when the main actor has allowed cursor
/// control (enabled, not paused, permission granted, camera running).
/// PHASE 2.1: PointerTracker wraps the HandPresenceFilter (strict acquisition, unchanged) and
/// decides whether an established hand may continue in a degraded mode near the frame edges.
/// @unchecked Sendable: `lock` guards the mailbox, counters and the cursor-allowed flag; the
/// engine, pointer tracker and cursor controller are confined to `visionQueue`.
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
    private var pointerTracker = PointerTracker()
    private var interactionEngine = InteractionEngine()
    private var cursorController = CursorController()
    /// PHASE 3B: drag anchor + primary-button ledger (the only place a mouseDown is recorded).
    private var dragController = DragController()
    private let events = MacOSEventController()
    private var lastHandCount = 0
    private var lastPointerMode: PointerTrackingMode = .lost
    private var consecutiveErrors = 0
    /// PHASE 3A-2 settings mirrored onto the Vision queue.
    private var scrollGesturesEnabled = AirTrackSettings.default.scrollGesturesEnabled
    private var scrollDirectionInverted = AirTrackSettings.default.scrollDirectionInverted
    /// PHASE 3B setting mirrored onto the Vision queue.
    private var clickGesturesEnabled = AirTrackSettings.default.clickGesturesEnabled

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
        // Pause, cursor control off, permission lost, camera stopped: close any live gesture
        // output right away (the camera may already be stopped, so no frame will do it):
        // scroll ended, click candidate dropped, mouseUp iff a drag holds the button.
        if changed, !allowed {
            visionQueue.async { [self] in closeInteraction(interactionEngine.cancel()) }
        }
    }

    /// App termination: close any live gesture output (open scroll, pressed button) before the
    /// process exits. Waits for the Vision queue (at most one frame of work); called once, from
    /// applicationWillTerminate.
    func shutdown() {
        lock.withLock { cursorAllowed = false }
        visionQueue.sync { [self] in closeInteraction(interactionEngine.cancel()) }
    }

    func apply(_ settings: AirTrackSettings) {
        visionQueue.async { [self] in
            cursorController.apply(settings)
            pointerTracker.apply(settings)
            interactionEngine.apply(settings)
            scrollGesturesEnabled = settings.scrollGesturesEnabled
            scrollDirectionInverted = settings.scrollDirectionInverted
            clickGesturesEnabled = settings.clickGesturesEnabled
            if !settings.scrollGesturesEnabled || !settings.clickGesturesEnabled {
                closeInteraction(interactionEngine.cancel())
            }
        }
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
            pointerTracker.reset()
            cursorController.reset()
            closeInteraction(interactionEngine.reset())
            if lastHandCount > 0 { Log.tracking.info("Tracking reset") }
            lastHandCount = 0
            lastPointerMode = .lost
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
        let tracked = pointerTracker.update(candidates: candidates, timestamp: frame.timestamp)
        let hands = tracked.hands
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
        if tracked.pointer.mode != lastPointerMode {
            Log.tracking.debug("Pointer \(tracked.pointer.mode.rawValue, privacy: .public)")
            lastPointerMode = tracked.pointer.mode
        }
        // PHASE 3A / 3B: the interaction engine sees every frame. A family's output reaches macOS
        // only while cursor control is allowed and that family is enabled; otherwise it only
        // observes (shadow mode) and the cursor path is exactly Phase 2.1.
        let allowed = lock.withLock { cursorAllowed }
        var outputs: InteractionOutputs = []
        if allowed, scrollGesturesEnabled { outputs.insert(.scroll) }
        if allowed, clickGesturesEnabled { outputs.insert(.pointerButton) }
        let interaction = interactionEngine.update(pointer: tracked.pointer, trackedHand: tracked.trackedHand, outputs: outputs)
        // Button actions first: a click or a mouseDown lands where the cursor is NOW (frozen
        // while the pinch was pending), before this frame moves anything.
        postButtons(interaction.actions)
        // Cursor policies sit ABOVE CursorController (never modified). Frozen: the controller is
        // not fed and is reset, so the cursor returns with the Phase 2.1 reacquisition glide.
        // Drag: the controller maps the index and DragController moves the cursor.
        let cursor = updateCursor(pointer: tracked.pointer, policy: interaction.appliedCursorPolicy,
                                  dragFollowsIndex: interaction.pinch.dragFollowsIndex)
        postInteraction(interaction.actions)
        onResult?(TrackingResult(
            hands: hands,
            candidateCount: candidates.count,
            rejections: pointerTracker.lastRejections,
            pointer: tracked.pointer,
            imageAspectRatio: frame.aspectRatio,
            interaction: interaction,
            cursor: cursor,
            primaryButtonDown: dragController.isButtonDown
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

    /// visionQueue. Moves the system cursor only for a trusted pointer while allowed. One
    /// writer per frame: CursorController (follow) or DragController (drag), never both.
    private func updateCursor(pointer: PointerObservation, policy: CursorPolicy, dragFollowsIndex: Bool) -> CursorUpdate? {
        let allowed = lock.withLock { cursorAllowed }
        // Invariant: the button is down only while an allowed drag owns the cursor.
        if dragController.isButtonDown, !allowed || policy != .drag { releaseButton() }
        guard allowed, policy != .frozen else {
            cursorController.reset()
            return nil
        }
        if policy == .drag { return updateDrag(pointer: pointer, followsIndex: dragFollowsIndex) }
        // Only read the real cursor position when a new session starts (reacquisition).
        let startsSession = pointer.startsSession || cursorController.needsReferencePosition
        let reference = pointer.mode.providesPointer && startsSession ? events.currentCursorLocation() : nil
        let update = cursorController.update(
            pointer: pointer,
            display: events.mainDisplayBounds(),
            isActive: true,
            currentCursor: reference
        )
        if let update {
            events.moveCursor(to: update.screen)
        }
        return update
    }

    /// visionQueue. PHASE 3B drag: the index goes through the Phase 2.1 mapping (active area,
    /// mirror, dead zone, sensitivity, smoothing; no reacquisition blend) and DragController
    /// adds the fixed anchor offset. Posted as leftMouseDragged, which also moves the cursor.
    /// Nothing is posted without a fresh index (HOLD) or while the pinch is uncertain.
    private func updateDrag(pointer: PointerObservation, followsIndex: Bool) -> CursorUpdate? {
        let display = events.mainDisplayBounds()
        let mapped = cursorController.update(pointer: pointer, display: display, isActive: true, currentCursor: nil)
        guard followsIndex, let mapped,
              let position = dragController.follow(index: mapped.normalized),
              let screen = ScreenMapper.map(position, to: display)
        else { return nil }
        events.postLeftMouseDragged(to: screen)
        // Report the drag position (the cursor's real position), keeping the mapping diagnostics.
        var update = mapped
        update.normalized = position
        update.screen = screen
        return update
    }

    /// visionQueue. PHASE 3B button actions, through the DragController ledger: a second
    /// mouseDown is never sent, a mouseUp only after a mouseDown, and no click while the
    /// button is held.
    private func postButtons(_ actions: [InteractionAction]) {
        for action in actions {
            switch action {
            case .leftClick:
                guard !dragController.isButtonDown, let at = events.currentCursorLocation() else { continue }
                events.postLeftClick(at: at)
                Log.tracking.debug("Left click")
            case .beginDrag:
                let display = events.mainDisplayBounds()
                guard display.isValid, let at = events.currentCursorLocation(),
                      dragController.press(at: display.normalizedPosition(of: at))
                else { continue }
                events.postLeftMouseDown(at: at)
                Log.tracking.debug("Drag began")
            case .endDrag:
                releaseButton()
            case .scroll, .moveCursor, .mouseDown, .mouseDrag, .mouseUp:
                break
            }
        }
    }

    /// visionQueue. mouseUp iff the ledger holds the button (idempotent), where the drag is.
    /// The cursor then resumes with the Phase 2.1 reacquisition glide from the drop point.
    private func releaseButton() {
        guard let position = dragController.release() else { return }
        let display = events.mainDisplayBounds()
        let at = ScreenMapper.map(position, to: display)
            ?? events.currentCursorLocation()
            ?? Point2D(x: display.x, y: display.y)
        events.postLeftMouseUp(at: at)
        cursorController.reset()
        Log.tracking.debug("Drag ended")
    }

    /// visionQueue. Ends every gesture and leaves nothing owed to macOS: closing scroll phases,
    /// the drag's mouseUp, and a final ledger check so no path can leave the button down.
    private func closeInteraction(_ closing: [InteractionAction]) {
        postButtons(closing)
        postInteraction(closing)
        releaseButton()
    }

    /// visionQueue. Posts scroll actions. The engine only produces them while output is live,
    /// plus the closing phases when it is switched off, which are always safe to post.
    private func postInteraction(_ actions: [InteractionAction]) {
        guard !actions.isEmpty else { return }
        events.post(actions, invertScroll: scrollDirectionInverted)
    }
}
