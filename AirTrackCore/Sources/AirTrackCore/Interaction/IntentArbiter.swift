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
    /// FULL tracking with measurable features.
    case available
    /// PointerTracker HOLD: short gap, no fresh landmarks, continuity preserved.
    case gap
    /// PARTIAL / INDEX, or a FULL hand without a measurable scale: cursor only, no gestures.
    case degraded
    /// PointerTracker LOST.
    case lost

    public init(mode: PointerTrackingMode, hasFeatures: Bool) {
        switch mode {
        case .full: self = hasFeatures ? .available : .degraded
        case .holding: self = .gap
        case .partial, .indexContinuity: self = .degraded
        case .lost: self = .lost
        }
    }
}

public enum ReleaseReason: String, Equatable, Sendable {
    /// The pose ended (e.g. the middle finger bent). Clean end of the gesture.
    case gestureEnded
    /// Tracking degraded to PARTIAL / INDEX: fresh gesture features are gone.
    case trackingDegraded
    /// PointerTracker LOST: data is stale.
    case trackingLost
    /// Pause, cursor control off, permission lost, camera stopped, shutdown, reset.
    case cancelled
}

public struct ArbiterConfiguration: Equatable, Sendable {
    /// Consecutive frames the active gesture may miss its pose before it is released.
    public var releaseFrames: Int = 2

    public init() {}
}

/// The single point that commits an intent. Rules:
/// 1. Recognizers may propose several candidates at once.
/// 2. Only the arbiter commits; one gesture owns the interaction at a time.
/// 3. Two candidates ready at the same time = ambiguity → no commit (no action).
/// 4. Evidence accumulates from the candidate's start (recognizers measure since then).
/// 5. No global neutral pose: a released family can start again as soon as its pose returns.
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
        /// The owner kept its pose this frame (scroll may produce deltas).
        public var held: Bool = false
        /// Several candidates were ready at once: nothing committed.
        public var ambiguous: Bool = false
    }

    public var configuration: ArbiterConfiguration
    public private(set) var lifecycle: InteractionLifecycle = .idle
    public private(set) var owner: GestureKind?
    public private(set) var candidateKind: GestureKind?
    public private(set) var candidateSince: TimeInterval?
    private var missingFrames = 0

    public init(configuration: ArbiterConfiguration = ArbiterConfiguration()) {
        self.configuration = configuration
    }

    public var candidateStarts: [GestureKind: TimeInterval] {
        guard let candidateKind, let candidateSince else { return [:] }
        return [candidateKind: candidateSince]
    }

    @discardableResult
    public mutating func update(candidates: [GestureCandidate], availability: FeatureAvailability) -> Decision {
        if let current = owner {
            return updateOwned(current, candidates: candidates, availability: availability)
        }
        return updateUnowned(candidates: candidates, availability: availability)
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
        missingFrames = 0
        lifecycle = .idle
        return previous
    }

    private mutating func updateOwned(_ current: GestureKind, candidates: [GestureCandidate], availability: FeatureAvailability) -> Decision {
        switch availability {
        case .gap:
            lifecycle = .suspended
            return Decision(lifecycle: lifecycle, owner: current)
        case .lost:
            return release(current, reason: .trackingLost)
        case .degraded:
            return release(current, reason: .trackingDegraded)
        case .available:
            if candidates.contains(where: { $0.kind == current && $0.continuesActive }) {
                missingFrames = 0
                lifecycle = .active
                return Decision(lifecycle: lifecycle, owner: current, held: true)
            }
            missingFrames += 1
            if missingFrames >= max(1, configuration.releaseFrames) {
                return release(current, reason: .gestureEnded)
            }
            lifecycle = .active
            return Decision(lifecycle: lifecycle, owner: current, held: false)
        }
    }

    private mutating func updateUnowned(candidates: [GestureCandidate], availability: FeatureAvailability) -> Decision {
        guard availability == .available, !candidates.isEmpty else {
            clearCandidate()
            return Decision(lifecycle: lifecycle)
        }
        let ready = candidates.filter(\.readyToCommit)
        let leading = ready.first ?? candidates.max(by: { $0.evidence < $1.evidence }) ?? candidates[0]
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
            missingFrames = 0
            lifecycle = .confirmed
            return Decision(lifecycle: lifecycle, owner: leading.kind, candidate: leading, committed: true, held: true)
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

    private mutating func release(_: GestureKind, reason: ReleaseReason) -> Decision {
        owner = nil
        missingFrames = 0
        candidateKind = nil
        candidateSince = nil
        lifecycle = .releasing
        return Decision(lifecycle: lifecycle, owner: nil, released: reason)
    }
}
