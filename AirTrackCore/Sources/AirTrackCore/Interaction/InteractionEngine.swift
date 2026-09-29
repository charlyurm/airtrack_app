import Foundation

/// Who drives the cursor this frame. The pipeline applies it ABOVE CursorController, which
/// itself never changes (Phase 2.1 is protected).
public enum CursorPolicy: String, Equatable, Sendable {
    /// Phase 2.1 behavior: the index moves the cursor.
    case follow
    /// A gesture owns the hand: the cursor must not follow the index.
    case frozen
}

public struct InteractionConfiguration: Equatable, Sendable {
    public var features = HandFeatureConfiguration()
    public var pose = PoseConfiguration()
    public var scroll = ScrollRecognizerConfiguration()
    public var scrollOutput = ScrollConfiguration()
    public var arbiter = ArbiterConfiguration()
    /// A stable candidate of a cursor-freezing family freezes the cursor after this long,
    /// before it commits: freezing earlier makes pointing sticky, later lets the cursor drift
    /// while a scroll starts. UNCALIBRATED (spec: ~80–100 ms).
    public var freezeDelay: TimeInterval = 0.09
    /// Same meaning as AirTrackSettings.mirrorCamera: motion is judged in the user's view.
    public var mirrored = true

    public init() {}
}

/// One frame of the interaction layer: everything the debug UI shows and, from 3A-2 on,
/// the semantic actions for the macOS adapter.
public struct InteractionFrame: Equatable, Sendable {
    public var timestamp: TimeInterval
    public var trackingMode: PointerTrackingMode
    public var availability: FeatureAvailability
    public var features: HandFeatures?
    /// Pose after hysteresis, and the raw pose of this frame.
    public var pose: HandPose
    public var rawPose: HandPose
    public var candidate: GestureCandidate?
    /// Committed gesture owning the interaction.
    public var intent: GestureKind?
    public var lifecycle: InteractionLifecycle
    public var released: ReleaseReason?
    public var ambiguous: Bool
    public var cursorPolicy: CursorPolicy
    /// Palm speed in hand scales per second, and the axis of the recent motion.
    public var handSpeed: Double
    public var axis: DominantAxis
    /// PHASE 3A-2: scroll output state, content speed (points/s), last whole step, and whether
    /// the current scroll reaches macOS (live) or is only observed (shadow).
    public var scrollState: ScrollController.State
    public var scrollSpeed: Double
    public var scrollDelta: Int
    public var liveOutput: Bool
    public var actions: [InteractionAction]

    public static func idle(at timestamp: TimeInterval) -> InteractionFrame {
        InteractionFrame(
            timestamp: timestamp, trackingMode: .lost, availability: .lost, features: nil,
            pose: .unknown, rawPose: .unknown, candidate: nil, intent: nil, lifecycle: .idle,
            released: nil, ambiguous: false, cursorPolicy: .follow, handSpeed: 0, axis: .none,
            scrollState: .idle, scrollSpeed: 0, scrollDelta: 0, liveOutput: false, actions: []
        )
    }
}

/// PointerTracker frame → features → history → pose → recognizers → arbiter → lifecycle.
///
/// Pure and deterministic, called once per processed camera frame on the Vision queue (also
/// without a hand, so time-based output can advance). It never reads the clock and never
/// touches macOS: the pipeline posts whatever `actions` it returns.
///
/// Output: `emitsActions` false (default) = shadow mode, exactly PHASE 3A-1: recognition and
/// arbitration only, no actions, cursor policy advisory. `emitsActions` true (PHASE 3A-2) = a
/// scroll committed while live produces `.scroll` actions and the cursor policy is meant to be
/// applied. A live scroll whose output is switched off is closed immediately (ended phase);
/// a scroll committed in shadow stays shadow until it is released.
public struct InteractionEngine: Sendable {
    public var configuration: InteractionConfiguration
    public private(set) var history: FeatureHistory
    public private(set) var poseClassifier: PoseClassifier
    public private(set) var arbiter: IntentArbiter
    public private(set) var scroll: ScrollController
    /// The current scroll session reaches macOS.
    public private(set) var liveSession = false
    private let recognizers: [any GestureRecognizer]
    private var lastTimestamp: TimeInterval?

    public init(configuration: InteractionConfiguration = InteractionConfiguration()) {
        self.configuration = configuration
        self.history = FeatureHistory()
        self.poseClassifier = PoseClassifier(configuration: configuration.pose)
        self.arbiter = IntentArbiter(configuration: configuration.arbiter)
        self.scroll = ScrollController(configuration: configuration.scrollOutput)
        self.recognizers = [ScrollRecognizer(configuration: configuration.scroll)]
    }

    public mutating func apply(_ settings: AirTrackSettings) {
        let s = settings.sanitized
        configuration.mirrored = s.mirrorCamera
        scroll.sensitivity = s.scrollSensitivity
    }

    /// Poses that start a new interaction and therefore stop inertia (a trackpad stops
    /// momentum when touched again). Pointing does not: the cursor may move while it coasts.
    static func stopsMomentum(_ pose: HandPose) -> Bool {
        switch pose {
        case .twoFinger, .openHand, .fourFinger, .pinch: true
        case .pointing, .unknown: false
        }
    }

    /// - Parameters:
    ///   - pointer: PointerTracker's decision for this frame (tracking mode, timestamp).
    ///   - trackedHand: the hand PointerTracker followed this frame (nil in HOLD / LOST).
    ///   - emitsActions: output allowed (cursor control active and scroll gestures enabled).
    public mutating func update(pointer: PointerObservation, trackedHand: HandState?, emitsActions: Bool = false) -> InteractionFrame {
        let now = pointer.timestamp
        // A frame that is not newer than the previous one carries nothing new.
        let isFresh = now.isFinite && (lastTimestamp.map { now > $0 } ?? true)
        if isFresh { lastTimestamp = now }

        var features: HandFeatures?
        if isFresh, pointer.mode == .full, let hand = trackedHand, hand.timestamp >= now - 0.001 {
            features = HandFeatureExtractor.features(of: hand, configuration: configuration.features)
        }
        var availability = FeatureAvailability(mode: pointer.mode, hasFeatures: features != nil)
        if !isFresh, availability == .available { availability = .gap }

        switch availability {
        case .available:
            if let features {
                poseClassifier.update(features)
                history.append(features, pose: poseClassifier.stablePose, mirrored: configuration.mirrored)
            }
        case .gap:
            break // keep pose and history: continuity is PointerTracker's call
        case .degraded, .lost:
            poseClassifier.reset()
            history.clear()
        }

        var candidates: [GestureCandidate] = []
        if availability == .available, let features {
            let context = RecognitionContext(
                now: now,
                features: features,
                stablePose: poseClassifier.stablePose,
                rawPose: poseClassifier.rawPose,
                history: history,
                activeKind: arbiter.owner,
                candidateSince: arbiter.candidateStarts
            )
            for recognizer in recognizers { candidates += recognizer.candidates(in: context) }
        }

        let decision = arbiter.update(candidates: candidates, availability: availability)
        var output: [ScrollAction] = []

        // Output switched off (pause, permission, cursor control): close anything live now.
        if !emitsActions {
            output += scroll.cancel()
            liveSession = false
        }
        // A new interaction stops inertia.
        if scroll.state == .momentum,
           decision.candidate != nil || decision.committed || Self.stopsMomentum(poseClassifier.stablePose) {
            output += scroll.cancelMomentum()
        }

        if decision.committed {
            output += scroll.cancelMomentum()
            liveSession = emitsActions
            if liveSession {
                let step = history.lastStep().map { (dy: $0.motion.dy, dt: $0.dt) }
                output.append(scroll.begin(step: step))
            }
        } else if let reason = decision.released {
            if liveSession {
                // Inertia only from fresh motion: never after LOST (stale) or a cancellation.
                let momentum = reason == .gestureEnded || reason == .trackingDegraded
                output += scroll.end(allowMomentum: momentum, at: now)
            }
            liveSession = false
        } else if decision.owner != nil, liveSession, decision.held, let step = history.lastStep() {
            // Axis locked: only the vertical component scrolls.
            if let action = scroll.update(dy: step.motion.dy, dt: step.dt) { output.append(action) }
        } else if scroll.state == .momentum, emitsActions {
            if let action = scroll.tick(at: now) { output.append(action) }
        }

        if arbiter.lifecycle == .releasing, scroll.state != .momentum { arbiter.finishReleasing() }

        return makeFrame(now: now, pointer: pointer, availability: availability, features: features,
                         decision: decision, emitsActions: emitsActions, actions: output.map(InteractionAction.scroll))
    }

    /// Pause, cursor control off, permission lost, camera stopped, shutdown: ends any gesture
    /// and returns the actions that close live output (an open scroll or inertia).
    public mutating func cancel() -> [InteractionAction] {
        let closing = scroll.cancel()
        liveSession = false
        arbiter.cancelAll()
        return closing.map(InteractionAction.scroll)
    }

    /// Forget everything (camera restarted). Returns the closing actions, like `cancel`.
    @discardableResult
    public mutating func reset() -> [InteractionAction] {
        let closing = cancel()
        poseClassifier.reset()
        history.clear()
        lastTimestamp = nil
        return closing
    }

    func cursorPolicy(for decision: IntentArbiter.Decision, now: TimeInterval) -> CursorPolicy {
        if decision.owner != nil { return .frozen }
        if decision.lifecycle == .candidate, let candidate = decision.candidate,
           candidate.family.freezesCursor, now - candidate.since >= configuration.freezeDelay {
            return .frozen
        }
        return .follow
    }

    private func makeFrame(now: TimeInterval, pointer: PointerObservation, availability: FeatureAvailability, features: HandFeatures?, decision: IntentArbiter.Decision, emitsActions: Bool, actions: [InteractionAction]) -> InteractionFrame {
        let velocity = availability == .available ? history.velocity() : .zero
        let recent = availability == .available ? history.displacement(since: now - 0.2) : .zero
        return InteractionFrame(
            timestamp: now,
            trackingMode: pointer.mode,
            availability: availability,
            features: features,
            pose: poseClassifier.stablePose,
            rawPose: poseClassifier.rawPose,
            candidate: decision.candidate,
            intent: decision.owner,
            // Inertia still running = the released gesture is still RELEASING.
            lifecycle: scroll.state == .momentum ? .releasing : decision.lifecycle,
            released: decision.released,
            ambiguous: decision.ambiguous,
            cursorPolicy: cursorPolicy(for: decision, now: now),
            handSpeed: velocity.magnitude,
            axis: DominantAxis.of(recent, minimumMagnitude: configuration.scroll.minimumAxisMotion, ratio: configuration.scroll.axisRatio),
            scrollState: scroll.state,
            scrollSpeed: scroll.pointsPerSecond,
            scrollDelta: scroll.lastDelta,
            liveOutput: liveSession || (scroll.state == .momentum && emitsActions),
            actions: actions
        )
    }
}
