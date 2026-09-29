import Foundation

/// Who drives the cursor this frame. The pipeline applies it ABOVE CursorController, which
/// itself never changes (Phase 2.1 is protected).
public enum CursorPolicy: String, Equatable, Sendable {
    /// Phase 2.1 behavior: the index moves the cursor.
    case follow
    /// A gesture owns the hand: the cursor must not follow the index.
    case frozen
    /// PHASE 3B: a drag owns the cursor. The pipeline moves it with DragController (index
    /// through the Phase 2.1 mapping + fixed anchor offset) as the ONLY writer, with the
    /// primary button held.
    case drag
}

/// Which interaction output reaches macOS. The pipeline sets it from cursor control and the
/// per-family settings; a family not included runs in shadow mode (recognized, no actions,
/// its cursor policy not applied).
public struct InteractionOutputs: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    /// PHASE 3A-2 two-finger / open-hand scroll.
    public static let scroll = InteractionOutputs(rawValue: 1 << 0)
    /// PHASE 3B pinch: left click and drag (primary button).
    public static let pointerButton = InteractionOutputs(rawValue: 1 << 1)
    public static let all: InteractionOutputs = [.scroll, .pointerButton]
}

/// PHASE 3B diagnostics of the pinch (debug panel) and the drag hint for the pipeline.
public struct PinchStatus: Equatable, Sendable {
    /// Thumb–index tip distance / hand scale this frame (the pinch ratio).
    public var distance: Double?
    /// Weakest thumb / index tip confidence this frame.
    public var confidence: Double?
    public var phase: PinchPhase
    /// A pinch formed now could start a click / drag (false after a pinch that ended a scroll,
    /// until the fingers open).
    public var armed: Bool
    /// Net hand travel since the pinch was confirmed, and the drag threshold, hand scales.
    public var movement: Double
    public var dragThreshold: Double
    /// The session's primary button is down (live drag).
    public var buttonDown: Bool
    /// The drag cursor follows the index this frame. False while the drag is suspended
    /// (uncertain pinch, HOLD): it stays where it is, nothing stale or extrapolated.
    public var dragFollowsIndex: Bool
    /// How a pinch ended THIS frame, if one did.
    public var outcome: PinchOutcome?
    /// The current pinch reaches macOS.
    public var live: Bool

    public static let none = PinchStatus(distance: nil, confidence: nil, phase: .none, armed: true, movement: 0,
                                         dragThreshold: PinchIntentConfiguration().dragDistance, buttonDown: false,
                                         dragFollowsIndex: false, outcome: nil, live: false)
}

public struct InteractionConfiguration: Equatable, Sendable {
    public var features = HandFeatureConfiguration()
    public var pose = PoseConfiguration()
    public var scroll = ScrollRecognizerConfiguration()
    public var scrollOutput = ScrollConfiguration()
    /// PHASE 3B: pinch recognition and the click / drag decision.
    public var pinch = PinchRecognizerConfiguration()
    public var pinchIntent = PinchIntentConfiguration()
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
    /// What the interaction wants (advisory, also in shadow mode)…
    public var cursorPolicy: CursorPolicy
    /// …and what the pipeline must apply: `cursorPolicy` when the owning family's output
    /// reaches macOS, `.follow` otherwise (shadow never touches the cursor).
    public var appliedCursorPolicy: CursorPolicy
    /// Palm speed in hand scales per second, and the axis of the recent motion.
    public var handSpeed: Double
    /// Vertical palm velocity, hand scales/s (+ = down), and the owner's maintenance evidence.
    public var verticalVelocity: Double
    public var maintenance: MaintenanceEvidence?
    public var axis: DominantAxis
    /// PHASE 3A-2: scroll output state, content speed (points/s), last whole step, and whether
    /// the current scroll reaches macOS (live) or is only observed (shadow).
    public var scrollState: ScrollController.State
    public var scrollSpeed: Double
    public var scrollDelta: Int
    public var liveOutput: Bool
    /// PHASE 3B: pinch / click / drag diagnostics.
    public var pinch: PinchStatus
    public var actions: [InteractionAction]

    public static func idle(at timestamp: TimeInterval) -> InteractionFrame {
        InteractionFrame(
            timestamp: timestamp, trackingMode: .lost, availability: .lost, features: nil,
            pose: .unknown, rawPose: .unknown, candidate: nil, intent: nil, lifecycle: .idle,
            released: nil, ambiguous: false, cursorPolicy: .follow, appliedCursorPolicy: .follow, handSpeed: 0,
            verticalVelocity: 0, maintenance: nil, axis: .none,
            scrollState: .idle, scrollSpeed: 0, scrollDelta: 0, liveOutput: false, pinch: .none, actions: []
        )
    }
}

/// PointerTracker frame → features → history → pose → recognizers → arbiter → lifecycle →
/// output (ScrollController for scroll, PinchIntentController for click / drag).
///
/// Pure and deterministic, called once per processed camera frame on the Vision queue (also
/// without a hand, so time-based output can advance). It never reads the clock and never
/// touches macOS: the pipeline posts whatever `actions` it returns.
///
/// Output per family (`InteractionOutputs`): a family not included runs in shadow mode —
/// recognition and arbitration only, no actions, cursor policy advisory (PHASE 3A-1). A live
/// gesture whose output is switched off is closed immediately (scroll ended phase, mouseUp);
/// a gesture committed in shadow stays shadow until it is released.
public struct InteractionEngine: Sendable {
    public var configuration: InteractionConfiguration
    public private(set) var history: FeatureHistory
    public private(set) var poseClassifier: PoseClassifier
    public private(set) var arbiter: IntentArbiter
    public private(set) var scroll: ScrollController
    /// PHASE 3B: click / drag decision of the committed pinch.
    public private(set) var pinchIntent: PinchIntentController
    /// The current scroll session reaches macOS.
    public private(set) var liveSession = false
    /// PHASE 3B: see `RecognitionContext.pinchArmed`.
    public private(set) var pinchArmed = true
    private let recognizers: [any GestureRecognizer]
    private var lastTimestamp: TimeInterval?

    public init(configuration: InteractionConfiguration = InteractionConfiguration()) {
        self.configuration = configuration
        self.history = FeatureHistory()
        self.poseClassifier = PoseClassifier(configuration: configuration.pose)
        self.arbiter = IntentArbiter(configuration: configuration.arbiter)
        self.scroll = ScrollController(configuration: configuration.scrollOutput)
        self.pinchIntent = PinchIntentController(configuration: configuration.pinchIntent)
        self.recognizers = [
            ScrollRecognizer(configuration: configuration.scroll),
            PinchGestureRecognizer(configuration: configuration.pinch, pose: configuration.pose),
        ]
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

    /// PHASE 3A signature: `emitsActions` true = every family live, false = shadow.
    public mutating func update(pointer: PointerObservation, trackedHand: HandState?, emitsActions: Bool = false) -> InteractionFrame {
        update(pointer: pointer, trackedHand: trackedHand, outputs: emitsActions ? .all : [])
    }

    /// - Parameters:
    ///   - pointer: PointerTracker's decision for this frame (tracking mode, timestamp).
    ///   - trackedHand: the hand PointerTracker followed this frame (nil in HOLD / LOST).
    ///   - outputs: families whose output may reach macOS this frame.
    public mutating func update(pointer: PointerObservation, trackedHand: HandState?, outputs: InteractionOutputs) -> InteractionFrame {
        let now = pointer.timestamp
        // A frame that is not newer than the previous one carries nothing new.
        let isFresh = now.isFinite && (lastTimestamp.map { now > $0 } ?? true)
        if isFresh { lastTimestamp = now }

        // Features from the observation PointerTracker followed THIS frame: FULL (strict hand)
        // or PARTIAL / INDEX (degraded view, used only to keep a committed gesture going).
        var features: HandFeatures?
        if isFresh, pointer.mode.providesPointer, let hand = trackedHand, hand.timestamp >= now - 0.001 {
            // A partial view may borrow the hand's recent scale, only while a gesture is committed.
            let fallback = pointer.mode != .full && arbiter.owner != nil ? history.referenceScale : nil
            features = HandFeatureExtractor.features(of: hand, configuration: configuration.features, fallbackScale: fallback)
        }
        let availability = isFresh
            ? FeatureAvailability(mode: pointer.mode, hasFeatures: features != nil)
            : (pointer.mode == .lost ? .lost : .gap)

        var recordedStep: MotionVector?
        switch availability {
        case .available:
            if let features {
                poseClassifier.update(features)
                history.append(features, pose: poseClassifier.stablePose, mirrored: configuration.mirrored)
                recordedStep = history.latest?.time == features.timestamp ? history.latest?.step : nil
            }
        case .limited:
            // Motion is still measured (per knuckle); the pose is not re-judged from a partial view.
            if let features {
                history.append(features, pose: poseClassifier.stablePose, mirrored: configuration.mirrored)
                recordedStep = history.latest?.time == features.timestamp ? history.latest?.step : nil
            }
        case .gap:
            break // keep pose and history: continuity is PointerTracker's call
        case .lost:
            poseClassifier.reset()
            history.clear()
        }

        // PHASE 3B: a pinch formed while another gesture owns the hand (or its inertia runs)
        // belongs to that interaction; it is re-armed once the stable pose leaves pinch.
        if poseClassifier.stablePose != .pinch {
            pinchArmed = true
        } else if arbiter.owner.map({ $0.family != .pinch }) ?? false || scroll.state == .momentum {
            pinchArmed = false
        }

        var candidates: [GestureCandidate] = []
        if availability == .available || availability == .limited, let features {
            let context = RecognitionContext(
                now: now,
                features: features,
                stablePose: poseClassifier.stablePose,
                rawPose: poseClassifier.rawPose,
                history: history,
                activeKind: arbiter.owner,
                candidateSince: arbiter.candidateStarts,
                canInitiate: availability == .available,
                pinchArmed: pinchArmed
            )
            for recognizer in recognizers { candidates += recognizer.candidates(in: context) }
        }

        let decision = arbiter.update(candidates: candidates, availability: availability, now: now)
        var output: [ScrollAction] = []
        var pointerActions: [InteractionAction] = []
        var pinchOutcome: PinchOutcome?

        // Output switched off (pause, permission, cursor control, setting): close anything
        // live now — an open scroll or inertia, a pressed button.
        if !outputs.contains(.scroll) {
            output += scroll.cancel()
            liveSession = false
        }
        if !outputs.contains(.pointerButton) {
            pointerActions += pinchIntent.silence()
        }
        // A new interaction stops inertia.
        if scroll.state == .momentum,
           decision.candidate != nil || decision.committed || Self.stopsMomentum(poseClassifier.stablePose) {
            output += scroll.cancelMomentum()
        }

        if decision.committed, let owner = decision.owner {
            output += scroll.cancelMomentum()
            switch owner.family {
            case .scroll:
                liveSession = outputs.contains(.scroll)
                if liveSession {
                    let step = history.lastStep().map { (dy: $0.motion.dy, dt: $0.dt) }
                    output.append(scroll.begin(step: step))
                }
            case .pinch:
                pointerActions += pinchIntent.begin(at: now, features: features, pointer: pointer,
                                                    live: outputs.contains(.pointerButton))
            }
        } else if let reason = decision.released {
            if decision.releasedKind?.family == .pinch {
                // Click only from a clean, fresh release; a drag always ends with its mouseUp.
                pointerActions += pinchIntent.release(reason: reason, availability: availability, now: now)
                pinchOutcome = pinchIntent.lastOutcome
            } else if liveSession {
                // Inertia only from fresh motion: a clean end while the scroll was still
                // supported. Never after a timeout, LOST (stale) or a cancellation.
                let momentum = reason == .gestureEnded && decision.releasedFresh
                output += scroll.end(allowMomentum: momentum, at: now)
            }
            liveSession = false
        } else if decision.owner?.family == .pinch {
            pointerActions += pinchIntent.update(step: recordedStep, held: decision.held, availability: availability, now: now)
        } else if decision.owner != nil, liveSession, decision.held, let step = history.lastStep() {
            // Axis locked: only the vertical component scrolls.
            if let action = scroll.update(dy: step.motion.dy, dt: step.dt) { output.append(action) }
        } else if scroll.state == .momentum, outputs.contains(.scroll) {
            if let action = scroll.tick(at: now) { output.append(action) }
        }

        if arbiter.lifecycle == .releasing, scroll.state != .momentum { arbiter.finishReleasing() }

        return makeFrame(now: now, pointer: pointer, availability: availability, features: features,
                         decision: decision, outputs: outputs, pinchOutcome: pinchOutcome,
                         actions: output.map(InteractionAction.scroll) + pointerActions)
    }

    /// Pause, cursor control off, permission lost, camera stopped, shutdown: ends any gesture
    /// and returns the actions that close live output (an open scroll or inertia, and the
    /// mouseUp of a pressed drag). Never a click.
    public mutating func cancel() -> [InteractionAction] {
        let closing = scroll.cancel()
        liveSession = false
        let released = pinchIntent.cancel()
        arbiter.cancelAll()
        // A pinch still held when output resumes is not a new, intentional pinch.
        if poseClassifier.stablePose == .pinch { pinchArmed = false }
        return closing.map(InteractionAction.scroll) + released
    }

    /// Forget everything (camera restarted). Returns the closing actions, like `cancel`.
    @discardableResult
    public mutating func reset() -> [InteractionAction] {
        let closing = cancel()
        poseClassifier.reset()
        history.clear()
        lastTimestamp = nil
        pinchArmed = true
        return closing
    }

    func cursorPolicy(for decision: IntentArbiter.Decision, now: TimeInterval) -> CursorPolicy {
        if let owner = decision.owner {
            // A confirmed pinch freezes the cursor so the click lands where the user aimed
            // (the fingers closing move the index tip); a committed drag owns it.
            if owner.family == .pinch, pinchIntent.phase == .dragging { return .drag }
            return .frozen
        }
        if decision.lifecycle == .candidate, let candidate = decision.candidate,
           candidate.family.freezesCursor, now - candidate.since >= configuration.freezeDelay {
            return .frozen
        }
        return .follow
    }

    /// The policy only reaches the cursor when the family behind it is live.
    private func appliedCursorPolicy(_ policy: CursorPolicy, decision: IntentArbiter.Decision, outputs: InteractionOutputs) -> CursorPolicy {
        guard policy != .follow else { return .follow }
        let family = decision.owner?.family ?? decision.candidate?.family
        switch family {
        case .scroll?:
            return outputs.contains(.scroll) ? policy : .follow
        case .pinch?:
            if decision.owner != nil {
                // A drag moves the cursor only while its button is really down.
                guard let session = pinchIntent.session, session.live else { return .follow }
                return policy == .drag && !session.buttonDown ? .frozen : policy
            }
            return outputs.contains(.pointerButton) ? policy : .follow
        case nil:
            return .follow
        }
    }

    private func pinchStatus(features: HandFeatures?, decision: IntentArbiter.Decision, outcome: PinchOutcome?) -> PinchStatus {
        let session = pinchIntent.session
        var phase = pinchIntent.phase
        if phase == .none, pinchArmed, poseClassifier.rawPose == .pinch || poseClassifier.stablePose == .pinch {
            phase = .candidate
        }
        return PinchStatus(
            distance: features?.thumbIndexDistance,
            confidence: features?.pinchConfidence,
            phase: phase,
            armed: pinchArmed,
            movement: session?.movement.magnitude ?? 0,
            dragThreshold: pinchIntent.configuration.dragDistance,
            buttonDown: pinchIntent.isButtonDown,
            dragFollowsIndex: pinchIntent.isButtonDown && decision.owner == .pinch && decision.held,
            outcome: outcome,
            live: session?.live ?? false
        )
    }

    private func makeFrame(now: TimeInterval, pointer: PointerObservation, availability: FeatureAvailability, features: HandFeatures?, decision: IntentArbiter.Decision, outputs: InteractionOutputs, pinchOutcome: PinchOutcome?, actions: [InteractionAction]) -> InteractionFrame {
        let measured = availability == .available || availability == .limited
        let velocity = measured ? history.velocity() : .zero
        let recent = measured ? history.displacement(since: now - 0.2) : .zero
        let policy = cursorPolicy(for: decision, now: now)
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
            cursorPolicy: policy,
            appliedCursorPolicy: appliedCursorPolicy(policy, decision: decision, outputs: outputs),
            handSpeed: velocity.magnitude,
            verticalVelocity: velocity.dy,
            maintenance: decision.maintenance,
            axis: DominantAxis.of(recent, minimumMagnitude: configuration.scroll.minimumAxisMotion, ratio: configuration.scroll.axisRatio),
            scrollState: scroll.state,
            scrollSpeed: scroll.pointsPerSecond,
            scrollDelta: scroll.lastDelta,
            liveOutput: liveSession || (scroll.state == .momentum && outputs.contains(.scroll)),
            pinch: pinchStatus(features: features, decision: decision, outcome: pinchOutcome),
            actions: actions
        )
    }
}
