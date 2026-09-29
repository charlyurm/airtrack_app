import XCTest
@testable import AirTrackCore

/// Synthetic hands with explicit finger poses (PHASE 3A). Geometry is defined in units of
/// image height around `center`, fingers pointing up, at scale 1 (hand scale ≈ 0.135), then
/// rotated, scaled and squeezed horizontally by the image aspect ratio like a real camera.
enum TestPoses {
    enum Thumb {
        /// Away from the palm (open hand).
        case extended
        /// Across the palm (pointing, two fingers, four fingers).
        case folded
        /// Halfway: neither clearly extended nor folded.
        case uncertain
        /// Tip touching the index tip.
        case pinching
        /// Tip touching the middle tip.
        case touchingMiddle
    }

    static let pointing: FingerSet = [.index]
    static let twoFingers: FingerSet = [.index, .middle]
    static let fourFingers: FingerSet = [.index, .middle, .ring, .pinky]

    /// Offsets (scale 1, no rotation) for the requested pose.
    static func offsets(extended: FingerSet, thumb: Thumb) -> [HandJoint: Point2D] {
        var o = TestHands.openHandOffsets
        let fingers: [(Finger, HandJoint, HandJoint, HandJoint, HandJoint)] = [
            (.index, .indexMCP, .indexPIP, .indexDIP, .indexTip),
            (.middle, .middleMCP, .middlePIP, .middleDIP, .middleTip),
            (.ring, .ringMCP, .ringPIP, .ringDIP, .ringTip),
            (.pinky, .pinkyMCP, .pinkyPIP, .pinkyDIP, .pinkyTip),
        ]
        for (finger, mcp, pip, dip, tip) in fingers where !extended.contains(FingerSet(finger)) {
            // Curled: PIP stays up, DIP folds back, tip ends below the knuckle (toward the wrist).
            let m = o[mcp]!
            let p = o[pip]!
            let bentPIP = m + (p - m) * 0.8
            o[pip] = bentPIP
            o[dip] = bentPIP + Point2D(x: 0, y: 0.025)
            o[tip] = m + Point2D(x: 0, y: 0.02)
        }
        switch thumb {
        case .extended:
            break
        case .folded:
            o[.thumbMP] = Point2D(x: -0.06, y: 0.07)
            o[.thumbIP] = Point2D(x: -0.03, y: 0.05)
            o[.thumbTip] = Point2D(x: 0.0, y: 0.04)
        case .uncertain:
            o[.thumbMP] = Point2D(x: -0.075, y: 0.07)
            o[.thumbIP] = Point2D(x: -0.075, y: 0.045)
            o[.thumbTip] = Point2D(x: -0.069, y: 0.0225)
        case .pinching:
            let target = o[.indexTip]! + Point2D(x: 0.012, y: 0.012)
            o[.thumbMP] = Point2D(x: -0.075, y: 0.04)
            o[.thumbIP] = (o[.thumbMP]! + target) * 0.5
            o[.thumbTip] = target
        case .touchingMiddle:
            let target = o[.middleTip]! + Point2D(x: 0.005, y: 0.01)
            o[.thumbMP] = Point2D(x: -0.075, y: 0.04)
            o[.thumbIP] = (o[.thumbMP]! + target) * 0.5
            o[.thumbTip] = target
        }
        return o
    }

    /// - Parameters:
    ///   - center: image position of the hand's reference origin (between knuckles and wrist).
    ///   - rotation: radians, in the image plane.
    ///   - aspect: image width / height (16:9 camera = 1.777…).
    static func hand(
        extended: FingerSet,
        thumb: Thumb = .folded,
        at time: TimeInterval = 0,
        center: Point2D = Point2D(x: 0.5, y: 0.5),
        scale: Double = 1,
        rotation: Double = 0,
        aspect: Double = 1,
        jointConfidence: Double = 0.9,
        handConfidence: Double = 0.95,
        chirality: HandChirality = .unknown,
        omit: Set<HandJoint> = [],
        noise: Double = 0,
        generator: inout SeededGenerator
    ) -> HandState {
        let c = cos(rotation)
        let s = sin(rotation)
        var landmarks: [HandJoint: HandLandmark] = [:]
        for (joint, offset) in offsets(extended: extended, thumb: thumb) where !omit.contains(joint) {
            let r = Point2D(x: offset.x * c - offset.y * s, y: offset.x * s + offset.y * c) * scale
            var p = Point2D(x: center.x + r.x / aspect, y: center.y + r.y)
            if noise > 0 {
                p = p + Point2D(x: Double.random(in: -noise...noise, using: &generator) / aspect,
                                y: Double.random(in: -noise...noise, using: &generator))
            }
            landmarks[joint] = HandLandmark(p, confidence: jointConfidence)
        }
        return HandState(timestamp: time, landmarks: landmarks, imageAspectRatio: aspect, chirality: chirality, confidence: handConfidence)
    }

    /// Convenience without noise.
    static func hand(
        extended: FingerSet,
        thumb: Thumb = .folded,
        at time: TimeInterval = 0,
        center: Point2D = Point2D(x: 0.5, y: 0.5),
        scale: Double = 1,
        rotation: Double = 0,
        aspect: Double = 1,
        jointConfidence: Double = 0.9,
        chirality: HandChirality = .unknown,
        omit: Set<HandJoint> = []
    ) -> HandState {
        var generator = SeededGenerator(seed: 1)
        return hand(extended: extended, thumb: thumb, at: time, center: center, scale: scale, rotation: rotation,
                    aspect: aspect, jointConfidence: jointConfidence, chirality: chirality, omit: omit, generator: &generator)
    }

}

/// Feeds the interaction engine like the pipeline does: one PointerTracker decision per frame.
enum InteractionScenario {
    static let dt = 1.0 / 30

    static func pointer(_ mode: PointerTrackingMode, hand: HandState?, at t: TimeInterval) -> PointerObservation {
        PointerObservation(mode: mode, indexTip: hand?.position(of: .indexTip), indexConfidence: 0.9, timestamp: t)
    }

    @discardableResult
    static func feed(_ engine: inout InteractionEngine, _ hand: HandState?, mode: PointerTrackingMode = .full, at t: TimeInterval) -> InteractionFrame {
        engine.update(pointer: pointer(mode, hand: hand, at: t), trackedHand: mode.providesPointer ? hand : nil)
    }

    /// Hand in `pose` moving by `step` (image units per frame) from `start`, frames first..<last.
    static func moving(
        _ engine: inout InteractionEngine,
        extended: FingerSet,
        thumb: TestPoses.Thumb = .folded,
        from start: Point2D = Point2D(x: 0.5, y: 0.4),
        step: Point2D,
        frames: Range<Int>,
        scale: Double = 1
    ) -> [InteractionFrame] {
        frames.map { i in
            let t = Double(i) * dt
            let center = start + step * Double(i - frames.lowerBound)
            return feed(&engine, TestPoses.hand(extended: extended, thumb: thumb, at: t, center: center, scale: scale), at: t)
        }
    }
}
