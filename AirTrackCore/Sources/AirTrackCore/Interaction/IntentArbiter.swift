import Foundation

/// Lifecycle of the interaction the arbiter is resolving.
///
///     IDLE → CANDIDATE → CONFIRMED → ACTIVE → RELEASING → IDLE
///     CANDIDATE → CANCELLED → IDLE
///     ACTIVE → SUSPENDED → ACTIVE      (PointerTracker HOLD, then recovery)
///     ACTIVE → SUSPENDED → RELEASING   (HOLD, then LOST)
public enum InteractionLifecycle: String, Equatable, Sendable {
    case idle
    case candidate
    case confirmed
    case active
    case suspended
    case releasing
    case cancelled
}

/// What the engine can see this frame. Derived from PointerTracker (the single source of
/// truth for continuity): no second tracking-loss timer exists in the interaction layer.
public enum FeatureAvailability: String, Equatable, Sendable {
    /// FULL tracking with measurable features: gestures may start and continue.
    case available
    /// PARTIAL / INDEX tracking with measurable features (e.g. the wrist below the frame while
    /// scrolling down): an active gesture may continue, a new one may not start.
    case limited
    /// No usable fresh features this frame (PointerTracker HOLD, stale frame, unmeasurable
    /// hand): an active gesture holds without output, bounded in time.
    case gap
    /// PointerTracker LOST.
    case lost

    public init(mode: PointerTrackingMode, hasFeatures: Bool) {
        switch mode {
        case .full: self = hasFeatures ? .available : .gap
        case .partial, .indexContinuity: self = hasFeatures ? .limited : .gap
        case .holding: self = .gap
        case .lost: self = .lost
        }
    }
}

public enum ReleaseReason: String, Equatable, Sendable {
    /// A stable, clearly different pose (e.g. the middle finger bent). Clean end.
    case gestureEnded
    /// No supporting evidence for longer than the maintenance grace.
    case recognitionTimeout
    /// PointerTracker LOST: data is stale.
    case trackingLost
    /// Pause, cursor control off, permission lost, camera stopped, shutdown, reset.
    case cancelled
}

public struct ArbiterConfiguration: Equatable, Sendable {
    /// How long a committed gesture survives without supporting evidence (UNKNOWN fingers,
    /// PointerTracker HOLD, a partial view without features) before it is released. Long
    /// enough to ride out blur and perspective changes of a moving hand (several frames at
    /// 30 fps), short enough that a relaxed hand does not stay "scrolling". UNCALIBRATED.
    public var maintenanceGrace: TimeInterval = 0.25
    /// A release counts as "fresh" (inertia allowed) only if the gesture was still supported
    /// this recently: inertia never starts from stale motion.
    public var freshReleaseWindow: TimeInterval = 0.1

    public init() {}
}

/// The single point that commits an intent. Rules:
/// 1. Recognizers may propose several candidates at once.
/// 2. Only the arbiter commits; one gesture owns the interaction at a time.
/// 3. Two candidates ready at the same time = ambiguity → no commit (no action).
/// 4. Evidence accumulates from the candidate's start (recognizers measure since then).
/// 5. No global neutral pose: a released family can start again as soon as its pose returns.
/// 6. Pre-confirmation: precision (strict pose, FULL tracking). Post-confirmation: temporal
///    continuity — uncertainty holds the gesture (SUSPENDED, no output) for at most
///    `maintenanceGrace`; only contradiction, the timeout, LOST or a cancel end it.
public struct IntentArbiter: Sendable {
    public struct Decision: Equatable, Sendable {
        public var lifecycle: InteractionLifecycle
        /// Owner of the interaction after this frame (CONFIRMED / ACTIVE / SUSPENDED).
        public var owner: GestureKind?
        /// Leading candidate while nothing is committed (diagnostics, cursor freeze timing).
        public var candidate: GestureCandidate?
        /// The owner committed this frame.
        public var committed: Bool = false
        /// The owner was released this frame, and why.
        public var released: ReleaseReason?
        /// PHASE 3B: which gesture was released this frame (its family decides the output).
        public var releasedKind: GestureKind?
        /// The release happened while the gesture was still recently supported (inertia OK).
        public var releasedFresh: Bool = false
        /// The owner is supported this frame (it may produce output).
        public var held: Bool = false
        /// Several candidates were ready at once: nothing committed.
        public var ambiguous: Bool = false
        /// Maintenance evidence of the owner this frame (diagnostics).
        public var maintenance: MaintenanceEvidence?
    }

    public var configuration: ArbiterConfiguration
    public private(set) var lifecycle: InteractionLifecycle = .idle
    public private(set) var owner: GestureKind?
    public private(set) var candidateKind: GestureKind?
    public private(set) var candidateSince: TimeInterval?
    /// Last time the owner had supporting evidence.
    public private(set) var lastSupportedAt: TimeInterval?

    public init(configuration: ArbiterConfiguration = ArbiterConfiguration()) {
        self.configuration = configuration
    }

    public var candidateStarts: [GestureKind: TimeInterval] {
        guard let candidateKind, let candidateSince else { return [:] }
        return [candidateKind: candidateSince]
    }

    @discardableResult
    public mutating func update(candidates: [GestureCandidate], availability: FeatureAvailability, now: TimeInterval) -> Decision {
        if let current = owner {
            return updateOwned(current, candidates: candidates, availability: availability, now: now)
        }
        return updateUnowned(candidates: candidates, availability: availability, now: now)
    }

    /// The engine calls this when a released gesture has nothing left to do (no inertia).
    public mutating func finishReleasing() {
        if lifecycle == .releasing { lifecycle = .idle }
    }

    /// Ends everything immediately (pause, permission, camera, shutdown). Returns the owner
    /// that was active, if any, so the caller can terminate its output.
    @discardableResult
    public mutating func cancelAll() -> GestureKind? {
        let previous = owner
        owner = nil
        candidateKind = nil
        candidateSince = nil
        lastSupportedAt = nil
        lifecycle = .idle
        return previous
    }

    private mutating func updateOwned(_ current: GestureKind, candidates: [GestureCandidate], availability: FeatureAvailability, now: TimeInterval) -> Decision {
        if availability == .lost {
            return release(current, reason: .trackingLost, fresh: false)
        }
        var evidence = MaintenanceEvidence.uncertain
        if availability == .available || availability == .limited,
           let own = candidates.first(where: { $0.kind == current }), let maintenance = own.maintenance {
            evidence = maintenance
        }
        let supportedAt = lastSupportedAt ?? now
        switch evidence {
        case .contradicted:
            var decision = release(current, reason: .gestureEnded, fresh: now - supportedAt <= configuration.freshReleaseWindow)
            decision.maintenance = .contradicted
            return decision
        case .supported:
            lastSupportedAt = now
            lifecycle = .active
            return Decision(lifecycle: lifecycle, owner: current, held: true, maintenance: .supported)
        case .uncertain:
            if now - supportedAt > configuration.maintenanceGrace {
                var decision = release(current, reason: .recognitionTimeout, fresh: false)
                decision.maintenance = .uncertain
                return decision
            }
            lifecycle = .suspended
            return Decision(lifecycle: lifecycle, owner: current, held: false, maintenance: .uncertain)
        }
    }

    private mutating func updateUnowned(candidates: [GestureCandidate], availability: FeatureAvailability, now: TimeInterval) -> Decision {
        let fresh = candidates.filter { $0.maintenance == nil }
        guard availability == .available, !fresh.isEmpty else {
            clearCandidate()
            return Decision(lifecycle: lifecycle)
        }
        let ready = fresh.filter(\.readyToCommit)
        let leading = ready.first ?? fresh.max(by: { $0.evidence < $1.evidence }) ?? fresh[0]
        if candidateKind != leading.kind {
            candidateKind = leading.kind
            candidateSince = leading.since
        }
        if ready.count > 1 {
            lifecycle = .candidate
            return Decision(lifecycle: lifecycle, candidate: leading, ambiguous: true)
        }
        if ready.count == 1 {
            owner = leading.kind
            candidateKind = nil
            candidateSince = nil
            lastSupportedAt = now
            lifecycle = .confirmed
            return Decision(lifecycle: lifecycle, owner: leading.kind, candidate: leading, committed: true, held: true, maintenance: .supported)
        }
        // A new candidate while the previous gesture is still releasing (inertia): the engine
        // stops that output; the lifecycle now follows the new candidate.
        lifecycle = .candidate
        return Decision(lifecycle: lifecycle, candidate: leading)
    }

    private mutating func clearCandidate() {
        if lifecycle == .candidate {
            lifecycle = .cancelled
        } else if lifecycle == .cancelled {
            lifecycle = .idle
        }
        candidateKind = nil
        candidateSince = nil
    }

    private mutating func release(_ kind: GestureKind, reason: ReleaseReason, fresh: Bool) -> Decision {
        owner = nil
        candidateKind = nil
        candidateSince = nil
        lastSupportedAt = nil
        lifecycle = .releasing
        return Decision(lifecycle: lifecycle, owner: nil, released: reason, releasedKind: kind, releasedFresh: fresh)
    }
}
