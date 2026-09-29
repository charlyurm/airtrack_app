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
    /// The active gesture still has its pose (continuation), even if not ready to commit.
    public var continuesActive: Bool
}

public struct RecognitionContext: Sendable {
    public var now: TimeInterval
    public var features: HandFeatures
    public var stablePose: HandPose
    public var rawPose: HandPose
    public var history: FeatureHistory
    /// Gesture currently owning the interaction (continuation rules apply to it).
    public var activeKind: GestureKind?
    /// Start time of the current candidate, per kind (from the arbiter).
    public var candidateSince: [GestureKind: TimeInterval]
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

/// Two-finger and open-hand vertical scroll. Entry needs the STABLE pose (hysteresis) and
/// vertically dominant travel; an active scroll only needs its fingers to keep the pose
/// (relaxed rules, so one uncertain finger does not break a scroll in progress).
public struct ScrollRecognizer: GestureRecognizer {
    public var configuration: ScrollRecognizerConfiguration

    public init(configuration: ScrollRecognizerConfiguration = ScrollRecognizerConfiguration()) {
        self.configuration = configuration
    }

    public func candidates(in context: RecognitionContext) -> [GestureCandidate] {
        var result: [GestureCandidate] = []
        for kind in GestureKind.allCases where kind.family == .scroll {
            let isActive = context.activeKind == kind
            if isActive {
                guard Self.continues(kind, features: context.features, rawPose: context.rawPose) else { continue }
            } else {
                guard context.activeKind == nil, context.stablePose == kind.pose else { continue }
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
                readyToCommit: axis == .vertical && vertical >= configuration.commitDistance,
                continuesActive: isActive
            ))
        }
        return result
    }

    /// Relaxed pose check for a scroll already in progress.
    static func continues(_ kind: GestureKind, features f: HandFeatures, rawPose: HandPose) -> Bool {
        if rawPose == .pinch || rawPose == .pointing { return false }
        let index = f.state(of: .index)
        let middle = f.state(of: .middle)
        let ring = f.state(of: .ring)
        let pinky = f.state(of: .pinky)
        switch kind {
        case .twoFingerScroll:
            return index == .extended && middle == .extended && ring != .extended && pinky != .extended
        case .openHandScroll:
            let four = [index, middle, ring, pinky]
            return index == .extended && middle == .extended && !four.contains(.bent)
                && four.filter { $0 == .extended }.count >= 3
        }
    }
}
