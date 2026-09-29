import Foundation

/// How the index tip that drives the cursor was obtained this frame (PHASE 2.1).
///
///     FULL → PARTIAL → INDEX CONTINUITY → (HOLDING) → LOST
///
/// - `full`: a hand that passes the strict HandValidation (all Phase 1.1 rules).
/// - `partial`: the ESTABLISHED hand, part of it outside the image (e.g. wrist below the
///   bottom edge), still with ≥ `minimumPartialJoints` confident joints.
/// - `indexContinuity`: the established hand reduced to its index finger (tip + at least one
///   other index joint), with a stricter tip confidence and a short time limit.
/// - `holding`: no trustworthy index THIS frame, but the last one is recent (≤ holdTimeout).
///   The cursor stays exactly where it is: no extrapolation, no stale movement.
/// - `lost`: no established hand. Only a strictly valid, acquired hand leaves this state.
public enum PointerTrackingMode: String, Equatable, Sendable, CaseIterable {
    case full
    case partial
    case indexContinuity
    case holding
    case lost

    /// Whether this frame carries a fresh index tip that may move the cursor.
    public var providesPointer: Bool {
        switch self {
        case .full, .partial, .indexContinuity: true
        case .holding, .lost: false
        }
    }

    /// Whether a hand is established (tracked, possibly degraded or briefly held).
    public var hasEstablishedHand: Bool { self != .lost }
}

/// The pointer decision for ONE frame. The index tip, when present, comes from this frame's
/// observation only; nothing is carried over or predicted.
public struct PointerObservation: Equatable, Sendable {
    public var mode: PointerTrackingMode
    /// Index tip in raw camera space (HandState convention). nil unless `mode.providesPointer`.
    public var indexTip: Point2D?
    public var indexConfidence: Double?
    public var timestamp: TimeInterval
    /// First pointer after `lost`: the cursor controller starts a new session.
    public var startsSession: Bool

    public init(mode: PointerTrackingMode, indexTip: Point2D? = nil, indexConfidence: Double? = nil, timestamp: TimeInterval, startsSession: Bool = false) {
        self.mode = mode
        self.indexTip = mode.providesPointer ? indexTip : nil
        self.indexConfidence = mode.providesPointer ? indexConfidence : nil
        self.timestamp = timestamp
        self.startsSession = startsSession
    }

    public static func lost(at timestamp: TimeInterval) -> PointerObservation {
        PointerObservation(mode: .lost, timestamp: timestamp)
    }

    public static func holding(at timestamp: TimeInterval) -> PointerObservation {
        PointerObservation(mode: .holding, timestamp: timestamp)
    }
}

public struct PointerTrackingFrame: Equatable, Sendable {
    /// Strictly validated, acquired hands (HandPresenceFilter output, unchanged from Phase 1.1).
    public var hands: [HandState]
    public var pointer: PointerObservation
}

/// Limits of degraded tracking. All values are UNCALIBRATED starting points (REQUIRES MACOS).
/// Distances are in image heights (aspect-corrected), times in seconds.
public struct PointerTrackingConfiguration: Equatable, Sendable {
    /// false = Phase 2 behavior: only an acquired full hand gives a pointer; any gap is `lost`.
    public var enabled: Bool
    /// Index tip confidence for a FULL hand (AirTrackSettings.minimumLandmarkConfidence).
    public var minimumLandmarkConfidence: Double
    /// Index tip confidence required to continue with a partial hand.
    public var partialIndexConfidence: Double
    /// Index tip confidence required when little more than the index is visible.
    public var indexOnlyConfidence: Double
    /// Confident joints (tip included) for `partial`; fewer → `indexContinuity`.
    public var minimumPartialJoints: Int
    /// Fastest plausible index motion between trusted observations.
    public var maximumSpeed: Double
    /// Allowed tip displacement = maximumSpeed · elapsed, clamped to minimumStep…maximumStep.
    public var minimumStep: Double
    public var maximumStep: Double
    /// Longest gap without a trustworthy index before the hand is `lost`.
    public var holdTimeout: TimeInterval
    /// Longest time without any FULL frame (partial, index-only and holding included).
    public var maximumDegradedDuration: TimeInterval
    /// Longest uninterrupted `indexContinuity` streak.
    public var maximumIndexOnlyDuration: TimeInterval
    /// Tip → nearest visible index joint, relative to the established hand size
    /// (wrist → indexMCP). Outside this range the "finger" is not plausible.
    public var segmentRatioRange: ClosedRange<Double>
    /// When the candidate still shows wrist and indexMCP, its size relative to the established hand.
    public var handScaleRange: ClosedRange<Double>
    /// Share of the joints visible in both frames that must move plausibly with the hand.
    public var minimumCoherentFraction: Double
    /// Observations older than the frame timestamp by more than this are stale.
    public var staleTolerance: TimeInterval

    public init(
        enabled: Bool = true,
        minimumLandmarkConfidence: Double = 0.3,
        partialIndexConfidence: Double = 0.5,
        indexOnlyConfidence: Double = 0.6,
        minimumPartialJoints: Int = 6,
        maximumSpeed: Double = 3.0,
        minimumStep: Double = 0.02,
        maximumStep: Double = 0.12,
        holdTimeout: TimeInterval = 0.15,
        maximumDegradedDuration: TimeInterval = 3.0,
        maximumIndexOnlyDuration: TimeInterval = 1.0,
        segmentRatioRange: ClosedRange<Double> = 0.05...1.5,
        handScaleRange: ClosedRange<Double> = 0.5...2.0,
        minimumCoherentFraction: Double = 0.5,
        staleTolerance: TimeInterval = 0.001
    ) {
        self.enabled = enabled
        self.minimumLandmarkConfidence = minimumLandmarkConfidence
        self.partialIndexConfidence = partialIndexConfidence
        self.indexOnlyConfidence = indexOnlyConfidence
        self.minimumPartialJoints = minimumPartialJoints
        self.maximumSpeed = maximumSpeed
        self.minimumStep = minimumStep
        self.maximumStep = maximumStep
        self.holdTimeout = holdTimeout
        self.maximumDegradedDuration = maximumDegradedDuration
        self.maximumIndexOnlyDuration = maximumIndexOnlyDuration
        self.segmentRatioRange = segmentRatioRange
        self.handScaleRange = handScaleRange
        self.minimumCoherentFraction = minimumCoherentFraction
        self.staleTolerance = staleTolerance
    }

    /// Finite values inside safe ranges. Degraded modes can only become stricter than the
    /// full-hand rule, never looser (e.g. partial confidence ≥ full confidence).
    public var sanitized: PointerTrackingConfiguration {
        let d = PointerTrackingConfiguration()
        func clamp(_ v: Double, _ lo: Double, _ hi: Double, _ fallback: Double) -> Double {
            v.isFinite ? min(max(v, lo), hi) : fallback
        }
        var s = self
        s.minimumLandmarkConfidence = clamp(minimumLandmarkConfidence, 0, 1, d.minimumLandmarkConfidence)
        s.partialIndexConfidence = clamp(partialIndexConfidence, s.minimumLandmarkConfidence, 1, max(d.partialIndexConfidence, s.minimumLandmarkConfidence))
        s.indexOnlyConfidence = clamp(indexOnlyConfidence, s.partialIndexConfidence, 1, max(d.indexOnlyConfidence, s.partialIndexConfidence))
        s.minimumPartialJoints = min(max(minimumPartialJoints, 2), HandJoint.allCases.count)
        s.maximumSpeed = clamp(maximumSpeed, 0, 10, d.maximumSpeed)
        s.maximumStep = clamp(maximumStep, 0, 0.5, d.maximumStep)
        s.minimumStep = clamp(minimumStep, 0, s.maximumStep, min(d.minimumStep, s.maximumStep))
        s.holdTimeout = clamp(holdTimeout, 0, 0.5, d.holdTimeout)
        s.maximumDegradedDuration = clamp(maximumDegradedDuration, 0, 10, d.maximumDegradedDuration)
        s.maximumIndexOnlyDuration = clamp(maximumIndexOnlyDuration, 0, s.maximumDegradedDuration, min(d.maximumIndexOnlyDuration, s.maximumDegradedDuration))
        if !(segmentRatioRange.lowerBound.isFinite && segmentRatioRange.upperBound.isFinite && segmentRatioRange.lowerBound >= 0) {
            s.segmentRatioRange = d.segmentRatioRange
        }
        if !(handScaleRange.lowerBound.isFinite && handScaleRange.upperBound.isFinite && handScaleRange.lowerBound > 0) {
            s.handScaleRange = d.handScaleRange
        }
        s.minimumCoherentFraction = clamp(minimumCoherentFraction, 0, 1, d.minimumCoherentFraction)
        s.staleTolerance = clamp(staleTolerance, 0, 0.1, d.staleTolerance)
        return s
    }
}

/// Decides, per frame, which index tip (if any) may drive the cursor (PHASE 2.1).
///
/// Acquisition is exactly the Phase 1.1 rule: HandPresenceFilter (strict validation + N
/// consecutive frames). Only after a hand has been acquired can a DEGRADED observation keep
/// it going, and only when it is evidently the same hand, observed now:
/// - fresh observation (not older than the frame), hand confidence ≥ the strict minimum;
/// - index tip confident (stricter than for a full hand) and inside the image;
/// - tip moved at most `maximumSpeed · elapsed` (clamped) from the last trusted tip;
/// - same chirality when both are known;
/// - plausible finger: another index joint visible at a plausible distance from the tip;
/// - consistent hand size when wrist and indexMCP are still visible;
/// - the other surviving joints moved coherently with the hand;
/// - time limits: `maximumDegradedDuration` without a full frame, `maximumIndexOnlyDuration`
///   of index-only, `holdTimeout` without any trustworthy index.
/// Anything else → `holding` (cursor still) and then `lost` (full reset; strict acquisition
/// again). Positions are never invented, extrapolated or reused.
///
/// Also bridges short dropouts of a FULL hand (motion blur, one missed Vision frame): a
/// strictly valid hand that continues the established one is used immediately instead of
/// waiting for the acquisition gate again.
///
/// Pure and deterministic; runs on the caller's queue, no timers.
public struct PointerTracker: Sendable {
    public var configuration: PointerTrackingConfiguration {
        didSet { configuration = configuration.sanitized }
    }
    public private(set) var presenceFilter: HandPresenceFilter
    public private(set) var mode: PointerTrackingMode = .lost
    private var session: Session?

    private struct Session: Sendable {
        var lastTip: Point2D
        var lastTime: TimeInterval
        var lastFullTime: TimeInterval
        var indexOnlySince: TimeInterval?
        /// wrist → indexMCP of the last full frame, in image heights.
        var handSize: Double
        var chirality: HandChirality
        /// Cleaned landmarks of the last trusted observation (coherence check only).
        var landmarks: [HandJoint: HandLandmark]
    }

    private struct Continuation {
        var mode: PointerTrackingMode
        var hand: HandState
        var tip: HandLandmark
        var displacement: Double
    }

    public init(filter: HandFilterConfiguration = HandFilterConfiguration(), configuration: PointerTrackingConfiguration = PointerTrackingConfiguration()) {
        self.presenceFilter = HandPresenceFilter(configuration: filter)
        self.configuration = configuration.sanitized
    }

    public var lastRejections: [HandRejectionReason] { presenceFilter.lastRejections }

    /// Settings that affect tracking (peripheral on/off, index confidence for full hands).
    public mutating func apply(_ settings: AirTrackSettings) {
        var c = configuration
        c.enabled = settings.cursorPeripheralTracking
        c.minimumLandmarkConfidence = settings.minimumLandmarkConfidence
        configuration = c
    }

    /// - Parameters:
    ///   - candidates: raw observations of ONE frame (any order, unvalidated).
    ///   - timestamp: capture time of that frame.
    public mutating func update(candidates: [HandState], timestamp: TimeInterval) -> PointerTrackingFrame {
        let hands = presenceFilter.update(candidates: candidates)
        let pointer = track(candidates: candidates, hands: hands, timestamp: timestamp)
        mode = pointer.mode
        return PointerTrackingFrame(hands: hands, pointer: pointer)
    }

    public mutating func reset() {
        presenceFilter.reset()
        session = nil
        mode = .lost
    }

    // MARK: - Decision

    private mutating func track(candidates: [HandState], hands: [HandState], timestamp t: TimeInterval) -> PointerObservation {
        let c = configuration
        guard t.isFinite else { return lose(at: t) }

        // 1. Acquired full hand (Phase 2 rule: the primary hand drives the cursor).
        if let primary = hands.first,
           let tip = primary.landmarks[.indexTip],
           tip.confidence >= c.minimumLandmarkConfidence, tip.position.isFinite {
            let starts = session == nil
            refreshFull(with: primary, tip: tip.position, at: t)
            return PointerObservation(mode: .full, indexTip: tip.position, indexConfidence: tip.confidence, timestamp: t, startsSession: starts)
        }

        // 2. Nothing established (or degraded tracking disabled): no pointer. Unknown partial
        //    detections never start cursor control.
        guard c.enabled, var s = session else { return lose(at: t) }

        let elapsed = t - s.lastTime
        guard elapsed > 0 else {
            // Not newer than the last trusted observation: nothing new to trust.
            return PointerObservation.holding(at: t)
        }

        // 3. Continuation of the established hand.
        if let found = bestContinuation(in: candidates, session: s, timestamp: t, elapsed: elapsed) {
            switch found.mode {
            case .full:
                refreshFull(with: found.hand, tip: found.tip.position, at: t)
                return PointerObservation(mode: .full, indexTip: found.tip.position, indexConfidence: found.tip.confidence, timestamp: t)
            case .partial:
                s.indexOnlySince = nil
            case .indexContinuity:
                if s.indexOnlySince == nil { s.indexOnlySince = t }
            case .holding, .lost:
                break
            }
            if t - s.lastFullTime > c.maximumDegradedDuration { return lose(at: t) }
            if let since = s.indexOnlySince, t - since > c.maximumIndexOnlyDuration { return lose(at: t) }
            s.lastTip = found.tip.position
            s.lastTime = t
            s.landmarks = found.hand.landmarks
            session = s
            return PointerObservation(mode: found.mode, indexTip: found.tip.position, indexConfidence: found.tip.confidence, timestamp: t)
        }

        // 4. No trustworthy index now: hold briefly, then lose.
        if elapsed <= c.holdTimeout, t - s.lastFullTime <= c.maximumDegradedDuration {
            return PointerObservation.holding(at: t)
        }
        return lose(at: t)
    }

    private mutating func lose(at t: TimeInterval) -> PointerObservation {
        session = nil
        return PointerObservation.lost(at: t)
    }

    private mutating func refreshFull(with hand: HandState, tip: Point2D, at t: TimeInterval) {
        let previous = session
        let size = hand.aspectCorrectedDistance(from: .wrist, to: .indexMCP) ?? previous?.handSize ?? presenceFilter.configuration.minimumHandSize
        let chirality = hand.chirality != .unknown ? hand.chirality : (previous?.chirality ?? .unknown)
        session = Session(
            lastTip: tip,
            lastTime: t,
            lastFullTime: t,
            indexOnlySince: nil,
            handSize: max(size, presenceFilter.configuration.minimumHandSize),
            chirality: chirality,
            landmarks: hand.landmarks
        )
    }

    private func bestContinuation(in candidates: [HandState], session s: Session, timestamp t: TimeInterval, elapsed: TimeInterval) -> Continuation? {
        let c = configuration
        let filter = presenceFilter.configuration
        let allowed = min(max(c.maximumSpeed * elapsed, c.minimumStep), c.maximumStep)
        var best: Continuation?

        for candidate in candidates {
            // Fresh observation from a plausible hand.
            guard candidate.timestamp.isFinite, candidate.timestamp >= t - c.staleTolerance,
                  candidate.confidence.isFinite, candidate.confidence >= filter.minimumHandConfidence
            else { continue }
            if s.chirality != .unknown, candidate.chirality != .unknown, candidate.chirality != s.chirality { continue }

            let strict: HandState?
            if case let .success(valid) = HandValidation.validate(candidate, configuration: filter) {
                strict = valid
            } else {
                strict = nil
            }
            let hand = strict ?? HandValidation.cleaned(candidate, configuration: filter)
            let requiredTipConfidence = strict != nil ? c.minimumLandmarkConfidence : c.partialIndexConfidence
            guard let tip = hand.landmarks[.indexTip], tip.confidence >= requiredTipConfidence else { continue }

            // Continuity: bounded displacement since the last trusted tip.
            let aspect = Self.aspect(of: hand)
            let displacement = Self.distance(tip.position, s.lastTip, aspect: aspect)
            guard displacement <= allowed else { continue }

            // Plausible index finger: another index joint at a finger-like distance.
            guard let support = [HandJoint.indexDIP, .indexPIP, .indexMCP].first(where: { hand.landmarks[$0] != nil }),
                  let segment = hand.aspectCorrectedDistance(from: .indexTip, to: support),
                  segment >= s.handSize * c.segmentRatioRange.lowerBound,
                  segment <= s.handSize * c.segmentRatioRange.upperBound
            else { continue }

            // Same hand size when it can still be measured.
            if let size = hand.aspectCorrectedDistance(from: .wrist, to: .indexMCP) {
                let ratio = size / s.handSize
                guard c.handScaleRange.contains(ratio) else { continue }
            }

            // The other surviving joints moved with the hand.
            guard Self.isCoherent(hand.landmarks, with: s.landmarks, aspect: aspect, bound: 2 * allowed, minimumFraction: c.minimumCoherentFraction) else { continue }

            let mode: PointerTrackingMode
            if strict != nil {
                mode = .full
            } else if hand.landmarks.count >= c.minimumPartialJoints {
                mode = .partial
            } else if tip.confidence >= c.indexOnlyConfidence {
                mode = .indexContinuity
            } else {
                continue
            }
            if best.map({ displacement < $0.displacement }) ?? true {
                best = Continuation(mode: mode, hand: hand, tip: tip, displacement: displacement)
            }
        }
        return best
    }

    private static func aspect(of hand: HandState) -> Double {
        (hand.imageAspectRatio.isFinite && hand.imageAspectRatio > 0) ? hand.imageAspectRatio : 1
    }

    /// Distance in image heights.
    private static func distance(_ a: Point2D, _ b: Point2D, aspect: Double) -> Double {
        let dx = (a.x - b.x) * aspect
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func isCoherent(
        _ current: [HandJoint: HandLandmark],
        with previous: [HandJoint: HandLandmark],
        aspect: Double,
        bound: Double,
        minimumFraction: Double
    ) -> Bool {
        var shared = 0
        var coherent = 0
        for (joint, landmark) in current where joint != .indexTip {
            guard let old = previous[joint] else { continue }
            shared += 1
            if distance(landmark.position, old.position, aspect: aspect) <= bound { coherent += 1 }
        }
        guard shared >= 2 else { return true }
        return Double(coherent) >= Double(shared) * minimumFraction
    }
}
