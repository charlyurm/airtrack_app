import Foundation

/// PHASE 3A: what the gesture engine knows about one hand in ONE frame.
///
/// Geometry is aspect-corrected (units of image height) and every distance a gesture uses is
/// divided by `scale`, so the same physical pose gives the same numbers near or far from the
/// camera and anywhere in the frame. Positions stay in the raw camera image (HandState
/// convention: top-left origin, y down, unmirrored); `FeatureHistory` turns motion into the
/// user's point of view.

public enum FingerState: String, Equatable, Sendable, CaseIterable {
    case extended
    case bent
    /// Not enough evidence either way (missing or low-confidence joints, foreshortened
    /// finger pointing at the camera, half-bent). Never forced into extended or bent.
    case unknown
}

/// A set of fingers, e.g. "index + middle". Keeps finger identity for recognizers.
public struct FingerSet: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let thumb = FingerSet(rawValue: 1 << 0)
    public static let index = FingerSet(rawValue: 1 << 1)
    public static let middle = FingerSet(rawValue: 1 << 2)
    public static let ring = FingerSet(rawValue: 1 << 3)
    public static let pinky = FingerSet(rawValue: 1 << 4)

    public init(_ finger: Finger) {
        switch finger {
        case .thumb: self = .thumb
        case .index: self = .index
        case .middle: self = .middle
        case .ring: self = .ring
        case .pinky: self = .pinky
        }
    }

    public var count: Int { rawValue.nonzeroBitCount }
}

public struct FingerFeature: Equatable, Sendable {
    public var state: FingerState
    /// Weakest joint confidence of the finger (0 when a joint is missing).
    public var confidence: Double
    /// Projected finger length (base → tip along the joints) / hand scale.
    public var length: Double?
    /// Base → tip distance / length along the joints: 1 = straight.
    public var straightness: Double?
}

public struct HandFeatures: Equatable, Sendable {
    public var timestamp: TimeInterval
    /// Robust hand size in image heights (largest rigid palm measurement, see extractor).
    public var scale: Double
    /// Mean of the visible knuckles (MCP joints), raw image space. Diagnostics / pose only:
    /// motion is measured per knuckle (FeatureHistory) so a knuckle dropping out of a frame
    /// never looks like movement.
    public var palmCenter: Point2D
    /// Visible knuckles (MCP joints), raw image space: the rigid reference for hand motion.
    public var knuckles: [HandJoint: Point2D]
    public var imageAspectRatio: Double
    public var chirality: HandChirality
    /// Vision's confidence that this is a hand.
    public var handConfidence: Double
    public var fingers: [Finger: FingerFeature]
    /// Fingertip distances / scale. nil when a tip is missing.
    public var thumbIndexDistance: Double?
    public var thumbMiddleDistance: Double?
    public var indexMiddleDistance: Double?
    /// PHASE 3B: weakest confidence of the thumb and index tips (nil when a tip is missing):
    /// how much the pinch distance can be trusted.
    public var pinchConfidence: Double?
    /// Joints available (0…21), a visibility summary.
    public var visibleJoints: Int

    public func state(of finger: Finger) -> FingerState { fingers[finger]?.state ?? .unknown }

    public var extendedFingers: FingerSet { fingerSet(in: .extended) }
    public var bentFingers: FingerSet { fingerSet(in: .bent) }
    public var extendedCount: Int { extendedFingers.count }

    private func fingerSet(in state: FingerState) -> FingerSet {
        var result: FingerSet = []
        for finger in Finger.allCases where self.state(of: finger) == state { result.insert(FingerSet(finger)) }
        return result
    }
}

/// Thresholds of the extractor, in hand-scale units. UNCALIBRATED (REQUIRES MACOS).
public struct HandFeatureConfiguration: Equatable, Sendable {
    public var minimumJointConfidence: Double = 0.3
    /// A finger this straight (base → tip / length along the joints) can be extended…
    public var extendedStraightness: Double = 0.8
    /// …if it is also at least this long (shorter = foreshortened, pointing at the camera).
    public var minimumExtendedLength: Double = 0.4
    /// At or below this straightness a finger is bent.
    public var bentStraightness: Double = 0.6
    /// Bent when the tip is closer to the wrist than this fraction of the PIP's distance.
    public var bentTipToWristRatio: Double = 0.9
    /// Shorter than this, nothing can be said (noise dominates).
    public var minimumMeasurableLength: Double = 0.2
    /// Thumb: tip → palm center distance for extended / bent.
    public var thumbExtendedDistance: Double = 0.75
    public var thumbBentDistance: Double = 0.5

    public init() {}
}

/// HandState → HandFeatures. Pure, no state. Returns nil when the hand cannot be measured
/// (no scale): the engine then treats the frame as "no features" → no gesture.
public enum HandFeatureExtractor {
    /// Palm width (indexMCP → pinkyMCP) is shorter than the palm length it stands in for.
    static let palmWidthToLength = 0.7
    public static let knuckleJoints: [HandJoint] = [.indexMCP, .middleMCP, .ringMCP, .pinkyMCP]

    /// - Parameter fallbackScale: used only when this frame's scale cannot be measured (e.g.
    ///   wrist and little-finger knuckle below the image while scrolling down). The engine
    ///   passes the recent median scale of the SAME tracked hand, and only for PARTIAL / INDEX
    ///   frames that can keep — never start — a gesture.
    public static func features(of hand: HandState, configuration c: HandFeatureConfiguration = HandFeatureConfiguration(), fallbackScale: Double? = nil) -> HandFeatures? {
        let aspect = (hand.imageAspectRatio.isFinite && hand.imageAspectRatio > 0) ? hand.imageAspectRatio : 1
        func point(_ joint: HandJoint) -> Point2D? { hand.position(of: joint, minimumConfidence: c.minimumJointConfidence) }
        func distance(_ a: Point2D, _ b: Point2D) -> Double {
            let dx = (a.x - b.x) * aspect
            let dy = a.y - b.y
            return (dx * dx + dy * dy).squareRoot()
        }

        let measured = HandFeatureExtractor.scale(of: hand, minimumConfidence: c.minimumJointConfidence)
        let usableFallback = fallbackScale.flatMap { $0.isFinite && $0 >= HandScale.minimumReferenceLength ? $0 : nil }
        guard let scale = measured ?? usableFallback, scale.isFinite, scale > 0 else { return nil }
        var knuckleMap: [HandJoint: Point2D] = [:]
        for joint in HandFeatureExtractor.knuckleJoints { knuckleMap[joint] = point(joint) }
        let knuckles = HandFeatureExtractor.knuckleJoints.compactMap { knuckleMap[$0] }
        guard !knuckles.isEmpty else { return nil }
        let palm = knuckles.reduce(Point2D.zero, +) * (1 / Double(knuckles.count))
        guard palm.isFinite else { return nil }
        let wrist = point(.wrist)

        var fingers: [Finger: FingerFeature] = [:]
        for finger in Finger.allCases {
            let chain = Array(HandSkeleton.chain(for: finger).dropFirst()) // base → tip, without the wrist
            let joints = chain.map { point($0) }
            let confidence = chain.map { hand.landmarks[$0]?.confidence ?? 0 }.min() ?? 0
            guard joints.allSatisfy({ $0 != nil }) else {
                fingers[finger] = FingerFeature(state: .unknown, confidence: confidence, length: nil, straightness: nil)
                continue
            }
            let p = joints.compactMap { $0 }
            var along = 0.0
            for i in 1..<p.count { along += distance(p[i - 1], p[i]) }
            let length = along / scale
            let straightness = along > 0 ? distance(p[0], p[p.count - 1]) / along : 0
            let state: FingerState
            if finger == .thumb {
                state = thumbState(tip: p[p.count - 1], palm: palm, length: length, scale: scale, distance: distance, c: c)
            } else {
                state = fingerState(tipToWrist: wrist.map { distance(p[p.count - 1], $0) },
                                    pipToWrist: wrist.map { distance(p[1], $0) },
                                    length: length, straightness: straightness, c: c)
            }
            fingers[finger] = FingerFeature(state: state, confidence: confidence, length: length, straightness: straightness)
        }

        func tipDistance(_ a: HandJoint, _ b: HandJoint) -> Double? {
            guard let p = point(a), let q = point(b) else { return nil }
            return distance(p, q) / scale
        }
        return HandFeatures(
            timestamp: hand.timestamp,
            scale: scale,
            palmCenter: palm,
            knuckles: knuckleMap,
            imageAspectRatio: aspect,
            chirality: hand.chirality,
            handConfidence: hand.confidence,
            fingers: fingers,
            thumbIndexDistance: tipDistance(.thumbTip, .indexTip),
            thumbMiddleDistance: tipDistance(.thumbTip, .middleTip),
            indexMiddleDistance: tipDistance(.indexTip, .middleTip),
            pinchConfidence: point(.thumbTip) != nil && point(.indexTip) != nil
                ? min(hand.landmarks[.thumbTip]?.confidence ?? 0, hand.landmarks[.indexTip]?.confidence ?? 0)
                : nil,
            visibleJoints: hand.landmarks.values.filter { $0.confidence >= c.minimumJointConfidence && $0.position.isFinite }.count
        )
    }

    /// Largest of several rigid palm measurements (wrist → index/middle/pinky knuckle, palm
    /// width). Foreshortening only ever shortens a segment, so the largest one is the best
    /// estimate of the real size; using several keeps it valid when the hand turns.
    public static func scale(of hand: HandState, minimumConfidence: Double = 0.3) -> Double? {
        var candidates: [Double] = []
        for knuckle in [HandJoint.indexMCP, .middleMCP, .pinkyMCP] {
            if let d = hand.aspectCorrectedDistance(from: .wrist, to: knuckle, minimumConfidence: minimumConfidence) { candidates.append(d) }
        }
        if let width = hand.aspectCorrectedDistance(from: .indexMCP, to: .pinkyMCP, minimumConfidence: minimumConfidence) {
            candidates.append(width / palmWidthToLength)
        }
        guard let best = candidates.filter(\.isFinite).max(), best >= HandScale.minimumReferenceLength else { return nil }
        return best
    }

    static func fingerState(tipToWrist: Double?, pipToWrist: Double?, length: Double, straightness: Double, c: HandFeatureConfiguration) -> FingerState {
        guard length.isFinite, straightness.isFinite, length >= c.minimumMeasurableLength else { return .unknown }
        if let tip = tipToWrist, let pip = pipToWrist, pip > 0, tip < pip * c.bentTipToWristRatio { return .bent }
        if straightness <= c.bentStraightness { return .bent }
        if straightness >= c.extendedStraightness, length >= c.minimumExtendedLength {
            // A straight finger must also point away from the wrist.
            if let tip = tipToWrist, let pip = pipToWrist, tip <= pip { return .unknown }
            return .extended
        }
        return .unknown
    }

    static func thumbState(tip: Point2D, palm: Point2D, length: Double, scale: Double, distance: (Point2D, Point2D) -> Double, c: HandFeatureConfiguration) -> FingerState {
        guard length.isFinite, length >= c.minimumMeasurableLength else { return .unknown }
        let reach = distance(tip, palm) / scale
        guard reach.isFinite else { return .unknown }
        if reach >= c.thumbExtendedDistance { return .extended }
        if reach <= c.thumbBentDistance { return .bent }
        return .unknown
    }
}
