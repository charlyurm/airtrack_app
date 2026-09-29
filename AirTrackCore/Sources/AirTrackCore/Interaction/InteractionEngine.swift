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
    public var actions: [InteractionAction]

    public static func idle(at timestamp: TimeInterval) -> InteractionFrame {
        InteractionFrame(
            timestamp: timestamp, trackingMode: .lost, availability: .lost, features: nil,
            pose: .unknown, rawPose: .unknown, candidate: nil, intent: nil, lifecycle: .idle,
            released: nil, ambiguous: false, cursorPolicy: .follow, handSpeed: 0, axis: .none, actions: []
        )
    }
}

/// PointerTracker frame → features → history → pose → recognizers → arbiter → lifecycle.
///
/// Pure and deterministic, called once per processed camera frame on the Vision queue (also
/// without a hand, so time-based output can advance). It never reads the clock and never
/// touches macOS: the pipeline posts whatever `actions` it returns.
///
/// PHASE 3A-1 (shadow): recognition and arbitration only; `actions` is always empty and the
/// cursor policy is advisory (the pipeline ignores it).
public struct InteractionEngine: Sendable {
    public var configuration: InteractionConfiguration
    public private(set) var history: FeatureHistory
    public private(set) var poseClassifier: PoseClassifier
    public private(set) var arbiter: IntentArbiter
    private let recognizers: [any GestureRecognizer]
    private var lastTimestamp: TimeInterval?

    public init(configuration: InteractionConfiguration = InteractionConfiguration()) {
        self.configuration = configuration
        self.history = FeatureHistory()
        self.poseClassifier = PoseClassifier(configuration: configuration.pose)
        self.arbiter = IntentArbiter(configuration: configuration.arbiter)
        self.recognizers = [ScrollRecognizer(configuration: configuration.scroll)]
    }

    public mutating func apply(_ settings: AirTrackSettings) {
        configuration.mirrored = settings.mirrorCamera
    }

    /// - Parameters:
    ///   - pointer: PointerTracker's decision for this frame (tracking mode, timestamp).
    ///   - trackedHand: the hand PointerTracker followed this frame (nil in HOLD / LOST).
    public mutating func update(pointer: PointerObservation, trackedHand: HandState?) -> InteractionFrame {
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
        if decision.lifecycle == .releasing { arbiter.finishReleasing() }

        return makeFrame(now: now, pointer: pointer, availability: availability, features: features, decision: decision, actions: [])
    }

    /// Pause, cursor control off, permission lost, camera stopped, shutdown: ends any gesture.
    /// Returns the actions that close live output (none in 3A-1).
    public mutating func cancel() -> [InteractionAction] {
        arbiter.cancelAll()
        return []
    }

    /// Forget everything (camera restarted).
    public mutating func reset() {
        arbiter.cancelAll()
        poseClassifier.reset()
        history.clear()
        lastTimestamp = nil
    }

    func cursorPolicy(for decision: IntentArbiter.Decision, now: TimeInterval) -> CursorPolicy {
        if decision.owner != nil { return .frozen }
        if decision.lifecycle == .candidate, let candidate = decision.candidate,
           candidate.family.freezesCursor, now - candidate.since >= configuration.freezeDelay {
            return .frozen
        }
        return .follow
    }

    private func makeFrame(now: TimeInterval, pointer: PointerObservation, availability: FeatureAvailability, features: HandFeatures?, decision: IntentArbiter.Decision, actions: [InteractionAction]) -> InteractionFrame {
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
            lifecycle: decision.lifecycle,
            released: decision.released,
            ambiguous: decision.ambiguous,
            cursorPolicy: cursorPolicy(for: decision, now: now),
            handSpeed: velocity.magnitude,
            axis: DominantAxis.of(recent, minimumMagnitude: configuration.scroll.minimumAxisMotion, ratio: configuration.scroll.axisRatio),
            actions: actions
        )
    }
}
