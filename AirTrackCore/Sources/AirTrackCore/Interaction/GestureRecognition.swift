import Foundation

/// Families own the interaction exclusively: one family at a time (IntentArbiter).
/// PHASE 3A implements `scroll`; future families (pinch, rightClick, swipe…) are added here.
public enum GestureFamily: String, Equatable, Sendable {
    case scroll

    /// Whether a stable candidate of this family freezes the cursor before it commits.
    public var freezesCursor: Bool {
        switch self {
        case .scroll: true
        }
    }
}

/// A concrete gesture a recognizer can propose. Finger identity + pose + motion.
public enum GestureKind: String, Equatable, Hashable, Sendable, CaseIterable {
    /// ☝️🖕 moving vertically.
    case twoFingerScroll
    /// 🖐️ moving vertically.
    case openHandScroll

    public var family: GestureFamily {
        switch self {
        case .twoFingerScroll, .openHandScroll: .scroll
        }
    }

    public var pose: HandPose {
        switch self {
        case .twoFingerScroll: .twoFinger
        case .openHandScroll: .openHand
        }
    }

    public var fingers: FingerSet {
        switch self {
        case .twoFingerScroll: [.index, .middle]
        case .openHandScroll: [.index, .middle, .ring, .pinky]
        }
    }
}

/// How well the current frame supports a gesture that is ALREADY committed.
///
/// Initiation and maintenance are different questions: starting needs the strict, stable pose
/// (precision first); keeping a committed gesture only needs the absence of contradiction
/// (temporal continuity first). Uncertainty holds the gesture briefly; only a clearly
/// different pose ends it at once.
public enum MaintenanceEvidence: String, Equatable, Sendable {
    /// The fingers still show the gesture: it may produce output.
    case supported
    /// Not enough evidence either way (UNKNOWN fingers, blur, partial view): hold, no output.
    case uncertain
    /// A stable, clearly different pose (e.g. pointing, pinch): the gesture has ended.
    case contradicted
}

/// "This looks like X": evidence only. Candidates never act; only the arbiter commits.
public struct GestureCandidate: Equatable, Sendable {
    public var kind: GestureKind
    public var family: GestureFamily { kind.family }
    public var fingers: FingerSet { kind.fingers }
    /// When this candidate started (pose became stable).
    public var since: TimeInterval
    /// Net motion since `since` (inside the history window), hand-scale units, user space.
    public var displacement: MotionVector
    public var axis: DominantAxis
    /// 0…1: how close the candidate is to commit.
    public var evidence: Double
    /// All commit conditions hold this frame.
    public var readyToCommit: Bool
    /// For the gesture that owns the interaction: this frame's maintenance evidence.
    /// nil for a candidate that is not committed.
    public var maintenance: MaintenanceEvidence?
}

public struct RecognitionContext: Sendable {
    public var now: TimeInterval
    public var features: HandFeatures
    public var stablePose: HandPose
    public var rawPose: HandPose
    public var history: FeatureHistory
    /// Gesture currently owning the interaction (maintenance rules apply to it).
    public var activeKind: GestureKind?
    /// Start time of the current candidate, per kind (from the arbiter).
    public var candidateSince: [GestureKind: TimeInterval]
    /// New gestures may start only with FULL tracking (strict features, fresh stable pose).
    /// PARTIAL / INDEX observations can only keep a gesture that is already committed.
    public var canInitiate: Bool = true
}

/// Stateless: all memory lives in the arbiter and the history, so recognizers are pure
/// functions of the context and easy to test. New gestures = new recognizers, not new
/// branches in a central switch.
public protocol GestureRecognizer: Sendable {
    func candidates(in context: RecognitionContext) -> [GestureCandidate]
}

/// Thresholds in hand-scale units. UNCALIBRATED (REQUIRES MACOS).
public struct ScrollRecognizerConfiguration: Equatable, Sendable {
    /// Vertical travel before a scroll commits (≈ 1–1.5 cm for an adult hand).
    public var commitDistance: Double = 0.12
    /// One axis must be this many times larger than the other to count as dominant.
    public var axisRatio: Double = 2.0
    /// Below this travel the axis is not judged at all.
    public var minimumAxisMotion: Double = 0.04

    public init() {}
}

/// Two-finger and open-hand vertical scroll.
/// - Initiation (precision): FULL tracking, the STABLE pose (hysteresis) and vertically
///   dominant travel of `commitDistance`.
/// - Maintenance (continuity): see `maintenance(of:features:stablePose:poseIsFresh:)`.
public struct ScrollRecognizer: GestureRecognizer {
    public var configuration: ScrollRecognizerConfiguration

    public init(configuration: ScrollRecognizerConfiguration = ScrollRecognizerConfiguration()) {
        self.configuration = configuration
    }

    public func candidates(in context: RecognitionContext) -> [GestureCandidate] {
        var result: [GestureCandidate] = []
        for kind in GestureKind.allCases where kind.family == .scroll {
            let isActive = context.activeKind == kind
            if !isActive {
                guard context.canInitiate, context.activeKind == nil, context.stablePose == kind.pose else { continue }
            }
            let since = context.candidateSince[kind] ?? context.now
            let from = max(since, context.now - context.history.window)
            let displacement = context.history.displacement(since: from)
            let axis = DominantAxis.of(displacement, minimumMagnitude: configuration.minimumAxisMotion, ratio: configuration.axisRatio)
            let vertical = abs(displacement.dy)
            let evidence = axis == .vertical ? min(1, vertical / configuration.commitDistance) : 0
            result.append(GestureCandidate(
                kind: kind,
                since: since,
                displacement: displacement,
                axis: axis,
                evidence: evidence,
                readyToCommit: !isActive && axis == .vertical && vertical >= configuration.commitDistance,
                maintenance: isActive
                    ? Self.maintenance(of: kind, features: context.features, stablePose: context.stablePose, poseIsFresh: context.canInitiate)
                    : nil
            ))
        }
        return result
    }

    /// Evidence for a scroll already in progress.
    /// - contradicted: the STABLE (debounced, FULL-tracking) pose is a clearly different one,
    ///   e.g. the middle finger bent (→ pointing) or a pinch. A real end, reacted to at once.
    /// - supported: the scrolling fingers are not bent and at least partly confirmed extended.
    ///   One UNKNOWN finger (blur, perspective while the hand moves) does not break it.
    /// - uncertain: anything else. The arbiter holds, bounded in time.
    static func maintenance(of kind: GestureKind, features f: HandFeatures, stablePose: HandPose, poseIsFresh: Bool) -> MaintenanceEvidence {
        if poseIsFresh, contradicts(kind, pose: stablePose) { return .contradicted }
        let index = f.state(of: .index)
        let middle = f.state(of: .middle)
        let ring = f.state(of: .ring)
        let pinky = f.state(of: .pinky)
        switch kind {
        case .twoFingerScroll:
            let fingersUp = index != .bent && middle != .bent && (index == .extended || middle == .extended)
            let othersDown = !(ring == .extended && pinky == .extended)
            return fingersUp && othersDown ? .supported : .uncertain
        case .openHandScroll:
            let four = [index, middle, ring, pinky]
            let open = !four.contains(.bent) && four.filter { $0 == .extended }.count >= 2
            return open ? .supported : .uncertain
        }
    }

    /// Stable poses that clearly mean "this scroll is over".
    static func contradicts(_ kind: GestureKind, pose: HandPose) -> Bool {
        switch (kind, pose) {
        case (_, .pointing), (_, .pinch): true
        case (.twoFingerScroll, .openHand), (.twoFingerScroll, .fourFinger): true
        case (.openHandScroll, .twoFinger): true
        default: false
        }
    }
}
