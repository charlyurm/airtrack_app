import Foundation

/// Pinch thresholds beyond the pose hysteresis. UNCALIBRATED (REQUIRES MACOS).
///
/// The enter / exit distances themselves live in `PoseConfiguration` (0.25 / 0.35 hand scales,
/// one source of truth for "is this a pinch"). With the Phase 3 hand scale (largest rigid palm
/// measurement, ≈ 9–11 cm on an adult hand) that is ≈ 2.5 cm to enter and ≈ 3.5 cm to leave:
/// touching fingertips measure ≈ 0.1–0.2 (Vision puts tip landmarks near the finger pads), a
/// relaxed pointing hand ≥ 0.6. The 0.1 band absorbs landmark jitter of a held pinch.
public struct PinchRecognizerConfiguration: Equatable, Sendable {
    /// Weakest thumb / index tip confidence needed to START a pinch (precision first). Once
    /// committed, tips measured at the feature minimum are enough to keep it (continuity).
    public var minimumInitiationConfidence: Double = 0.5
    /// Consecutive measured frames beyond the exit distance that end a pinch. One noisy open
    /// frame never releases (and therefore never clicks).
    public var releaseFrames: Int = 2

    public init() {}
}

/// 🤏 index + thumb pinch. Produces candidates only: whether it becomes a click or a drag is
/// decided later (PinchIntentController); nothing here reaches macOS.
///
/// - Initiation (precision): FULL tracking, nothing else owns the hand, the pinch is armed
///   (formed while idle), the STABLE pose is pinch (2 frames, PoseClassifier hysteresis), the
///   distance is inside the ENTER threshold and both tips are confidently measured.
/// - Maintenance (continuity): see `maintenance(features:history:exitDistance:releaseFrames:)`.
public struct PinchGestureRecognizer: GestureRecognizer {
    public var configuration: PinchRecognizerConfiguration
    public var enterDistance: Double
    public var exitDistance: Double

    public init(configuration: PinchRecognizerConfiguration = PinchRecognizerConfiguration(), pose: PoseConfiguration = PoseConfiguration()) {
        self.configuration = configuration
        self.enterDistance = pose.pinchEnterDistance
        self.exitDistance = pose.pinchExitDistance
    }

    public func candidates(in context: RecognitionContext) -> [GestureCandidate] {
        let kind = GestureKind.pinch
        let features = context.features
        if context.activeKind == kind {
            return [GestureCandidate(
                kind: kind, since: context.now, displacement: .zero, axis: .none, evidence: 1, readyToCommit: false,
                maintenance: Self.maintenance(features: features, history: context.history,
                                              exitDistance: exitDistance, releaseFrames: configuration.releaseFrames)
            )]
        }
        // Only a frame that is really pinched this frame (inside ENTER) is a candidate; the
        // hysteresis band keeps a pinch, it never starts one.
        guard context.canInitiate, context.activeKind == nil, context.pinchArmed, context.stablePose == .pinch,
              let distance = features.thumbIndexDistance, distance.isFinite, distance <= enterDistance
        else { return [] }
        let ready = (features.pinchConfidence ?? 0) >= configuration.minimumInitiationConfidence
        return [GestureCandidate(
            kind: kind,
            since: context.candidateSince[kind] ?? context.now,
            displacement: .zero,
            axis: .none,
            evidence: ready ? 1 : 0.5,
            readyToCommit: ready,
            maintenance: nil
        )]
    }

    /// Evidence for a pinch already committed. Based on the measured distance, not on the pose:
    /// a tight pinch can make the thumb look folded, and that must not end (or click) anything.
    /// - supported: the tips are measured and still within the EXIT distance (hysteresis band).
    /// - contradicted: the last `releaseFrames` measured frames are all beyond the exit
    ///   distance: the fingers really opened. This is the only clean release.
    /// - uncertain: a tip is missing (occlusion, blur, HOLD), or the opening is not confirmed
    ///   yet. The arbiter holds, bounded by its grace, and a timeout never clicks.
    static func maintenance(features: HandFeatures, history: FeatureHistory, exitDistance: Double, releaseFrames: Int) -> MaintenanceEvidence {
        guard let distance = features.thumbIndexDistance, distance.isFinite else { return .uncertain }
        if distance <= exitDistance { return .supported }
        let needed = max(1, releaseFrames)
        let recent = history.all.suffix(needed)
        let opened = recent.count == needed && recent.allSatisfy { sample in
            guard let d = sample.pinchDistance, d.isFinite else { return false }
            return d > exitDistance
        }
        return opened ? .contradicted : .uncertain
    }
}
