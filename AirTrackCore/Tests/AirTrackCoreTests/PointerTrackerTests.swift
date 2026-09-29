import XCTest
@testable import AirTrackCore

/// PHASE 2.1: FULL → PARTIAL → INDEX CONTINUITY → HOLDING → LOST.
/// Raw camera space (top-left, y down). Frames at 30 fps. Acquisition of a full hand takes the
/// Phase 1.1 gate of 2 consecutive valid frames.
final class PointerTrackerTests: XCTestCase {
    private let dt = 1.0 / 30
    private func t(_ frame: Int) -> TimeInterval { Double(frame) * dt }

    /// Lower part of the hand outside the image (wrist, thumb, knuckles): 11 joints remain.
    private static let lowerHand: Set<HandJoint> = [
        .wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
        .indexMCP, .middleMCP, .ringMCP, .pinkyMCP, .pinkyPIP,
    ]
    /// Only the index finger above the knuckle is visible.
    private static let allButIndex: Set<HandJoint> = Set(HandJoint.allCases).subtracting([.indexTip, .indexDIP, .indexPIP])

    private func center(for tip: Point2D) -> Point2D { tip - TestHands.openHandOffsets[.indexTip]! }

    private func full(_ tip: Point2D, _ time: TimeInterval, chirality: HandChirality = .unknown) -> HandState {
        TestHands.openHand(at: time, center: center(for: tip), chirality: chirality)
    }

    private func partial(_ tip: Point2D, _ time: TimeInterval, chirality: HandChirality = .unknown, indexConfidence: Double? = nil) -> HandState {
        var hand = TestHands.openHand(at: time, center: center(for: tip), chirality: chirality, omit: Self.lowerHand)
        if let indexConfidence { hand.landmarks[.indexTip]?.confidence = indexConfidence }
        return hand
    }

    private func indexOnly(_ tip: Point2D, _ time: TimeInterval, indexConfidence: Double = 0.9) -> HandState {
        var hand = TestHands.openHand(at: time, center: center(for: tip), omit: Self.allButIndex)
        hand.landmarks[.indexTip]?.confidence = indexConfidence
        return hand
    }

    /// Acquires a full hand at `tip` (frames 0 and 1) and returns the tracker in FULL.
    private func acquired(at tip: Point2D = Point2D(x: 0.5, y: 0.5), chirality: HandChirality = .unknown, configuration: PointerTrackingConfiguration = PointerTrackingConfiguration()) -> PointerTracker {
        var tracker = PointerTracker(configuration: configuration)
        XCTAssertEqual(tracker.update(candidates: [full(tip, t(0), chirality: chirality)], timestamp: t(0)).pointer.mode, .lost, "one frame is not enough")
        let second = tracker.update(candidates: [full(tip, t(1), chirality: chirality)], timestamp: t(1)).pointer
        XCTAssertEqual(second.mode, .full)
        XCTAssertTrue(second.startsSession)
        return tracker
    }

    // MARK: Full hand

    func testFullHandIsTrackedAfterStrictAcquisition() {
        var tracker = acquired()
        let tip = Point2D(x: 0.52, y: 0.5)
        let frame = tracker.update(candidates: [full(tip, t(2))], timestamp: t(2))
        XCTAssertEqual(frame.pointer.mode, .full)
        XCTAssertFalse(frame.pointer.startsSession)
        XCTAssertPointEqual(frame.pointer.indexTip, tip)
        XCTAssertEqual(frame.hands.count, 1, "strict hands are still reported for the overlay")
    }

    func testAcquiredFullHandAlwaysDrivesThePointerAsInPhase2() {
        var tracker = acquired()
        // A large but fully valid movement (fast hand): the strict path follows it.
        let far = Point2D(x: 0.2, y: 0.3)
        XCTAssertPointEqual(tracker.update(candidates: [full(far, t(2))], timestamp: t(2)).pointer.indexTip, far)
    }

    // MARK: Degraded continuation

    func testPartialHandAfterAcquisitionContinuesWithTheCurrentTip() {
        var tracker = acquired(at: Point2D(x: 0.5, y: 0.6))
        for i in 2..<20 {
            let tip = Point2D(x: 0.5, y: 0.6 + 0.01 * Double(i - 1))
            let frame = tracker.update(candidates: [partial(tip, t(i))], timestamp: t(i))
            XCTAssertEqual(frame.pointer.mode, .partial, "frame \(i)")
            XCTAssertPointEqual(frame.pointer.indexTip, tip)
            XCTAssertTrue(frame.hands.isEmpty, "a partial hand never becomes a strict hand")
        }
    }

    func testIndexContinuityAfterAcquisition() {
        var tracker = acquired()
        let tip = Point2D(x: 0.5, y: 0.51)
        let frame = tracker.update(candidates: [indexOnly(tip, t(2))], timestamp: t(2))
        XCTAssertEqual(frame.pointer.mode, .indexContinuity)
        XCTAssertPointEqual(frame.pointer.indexTip, tip)
    }

    func testDegradesStepByStepAndRecoversToFull() {
        var tracker = acquired()
        let tip = Point2D(x: 0.5, y: 0.5)
        XCTAssertEqual(tracker.update(candidates: [partial(tip, t(2))], timestamp: t(2)).pointer.mode, .partial)
        XCTAssertEqual(tracker.update(candidates: [indexOnly(tip, t(3))], timestamp: t(3)).pointer.mode, .indexContinuity)
        XCTAssertEqual(tracker.update(candidates: [], timestamp: t(4)).pointer.mode, .holding)
        XCTAssertEqual(tracker.update(candidates: [partial(tip, t(5))], timestamp: t(5)).pointer.mode, .partial)
        let back = tracker.update(candidates: [full(tip, t(6))], timestamp: t(6)).pointer
        XCTAssertEqual(back.mode, .full)
        XCTAssertFalse(back.startsSession, "same hand: no new session")
    }

    /// N2/N3: the hand slides down until only the fingers are inside the image.
    func testHandSlidingOutOfTheBottomEdgeKeepsTheIndex() {
        var tracker = acquired(at: Point2D(x: 0.5, y: 0.6))
        var tip = Point2D(x: 0.5, y: 0.6)
        var frame = 2
        while tip.y < 0.97 {
            tip = Point2D(x: 0.5, y: tip.y + 0.01)
            // Joints below the image (y > 1.05) are dropped by validation, as if Vision lost them.
            let observed = TestHands.openHand(at: t(frame), center: center(for: tip))
            let pointer = tracker.update(candidates: [observed], timestamp: t(frame)).pointer
            XCTAssertTrue(pointer.mode == .full || pointer.mode == .partial, "y \(tip.y): \(pointer.mode)")
            XCTAssertPointEqual(pointer.indexTip, tip)
            frame += 1
        }
        XCTAssertEqual(tracker.mode, .partial, "at the edge only a partial hand is visible")
    }

    // MARK: Safety

    func testIsolatedIndexOrPartialHandNeverStartsTracking() {
        var tracker = PointerTracker()
        for i in 0..<30 {
            let tip = Point2D(x: 0.5, y: 0.5)
            let a = tracker.update(candidates: [indexOnly(tip, t(i))], timestamp: t(i)).pointer
            XCTAssertEqual(a.mode, .lost)
            XCTAssertNil(a.indexTip)
        }
        for i in 30..<60 {
            let b = tracker.update(candidates: [partial(Point2D(x: 0.5, y: 0.5), t(i))], timestamp: t(i)).pointer
            XCTAssertEqual(b.mode, .lost, "an unknown partial hand must not activate the cursor")
            XCTAssertNil(b.indexTip)
        }
    }

    func testSuddenIndexJumpIsNotFollowed() {
        var tracker = acquired()
        let jumped = Point2D(x: 0.8, y: 0.5)
        var sawLost = false
        for i in 2..<12 {
            let pointer = tracker.update(candidates: [partial(jumped, t(i))], timestamp: t(i)).pointer
            XCTAssertNil(pointer.indexTip, "frame \(i): the jumped point must never drive the cursor")
            XCTAssertTrue(pointer.mode == .holding || pointer.mode == .lost)
            if pointer.mode == .lost { sawLost = true }
            if sawLost { XCTAssertEqual(pointer.mode, .lost, "stays lost until a full hand is acquired") }
        }
        XCTAssertTrue(sawLost, "the hold ends in a loss")
    }

    func testLowConfidenceIndexIsNotTrusted() {
        var tracker = acquired()
        let tip = Point2D(x: 0.5, y: 0.5)
        XCTAssertEqual(tracker.update(candidates: [partial(tip, t(2), indexConfidence: 0.4)], timestamp: t(2)).pointer.mode, .holding)
        // Index-only needs even more confidence than a partial hand.
        XCTAssertEqual(tracker.update(candidates: [indexOnly(tip, t(3), indexConfidence: 0.55)], timestamp: t(3)).pointer.mode, .holding)
        XCTAssertEqual(tracker.update(candidates: [indexOnly(tip, t(4), indexConfidence: 0.7)], timestamp: t(4)).pointer.mode, .indexContinuity)
    }

    func testStaleObservationIsNotTrusted() {
        var tracker = acquired()
        let old = partial(Point2D(x: 0.5, y: 0.5), t(2) - 0.1)
        let pointer = tracker.update(candidates: [old], timestamp: t(2)).pointer
        XCTAssertEqual(pointer.mode, .holding)
        XCTAssertNil(pointer.indexTip)
        // A frame that is not newer than the last trusted one is not trusted either.
        XCTAssertEqual(tracker.update(candidates: [partial(Point2D(x: 0.5, y: 0.5), t(1))], timestamp: t(1)).pointer.mode, .holding)
    }

    func testOtherHandChiralityIsNotTheSameHand() {
        var tracker = acquired(chirality: .right)
        let tip = Point2D(x: 0.5, y: 0.5)
        XCTAssertEqual(tracker.update(candidates: [partial(tip, t(2), chirality: .left)], timestamp: t(2)).pointer.mode, .holding)
        XCTAssertEqual(tracker.update(candidates: [partial(tip, t(3), chirality: .unknown)], timestamp: t(3)).pointer.mode, .partial, "unknown chirality is not a contradiction")
    }

    func testImplausibleFingerGeometryIsRejected() {
        var tracker = acquired()
        let tip = Point2D(x: 0.5, y: 0.5)
        var weird = indexOnly(tip, t(2))
        weird.landmarks[.indexDIP]?.position = tip + Point2D(x: 0, y: 0.35) // "finger" longer than a hand
        weird.landmarks[.indexPIP] = nil
        XCTAssertEqual(tracker.update(candidates: [weird], timestamp: t(2)).pointer.mode, .holding)
        var dot = indexOnly(tip, t(3))
        dot.landmarks = [.indexTip: HandLandmark(tip, confidence: 0.95)] // an isolated point
        XCTAssertEqual(tracker.update(candidates: [dot], timestamp: t(3)).pointer.mode, .holding)
    }

    func testIncoherentSurvivingJointsAreRejected() {
        var tracker = acquired()
        var mixed = partial(Point2D(x: 0.5, y: 0.5), t(2))
        // Index chain in place, but the other fingers are somewhere else entirely.
        for joint in [HandJoint.middlePIP, .middleDIP, .middleTip, .ringPIP, .ringDIP, .ringTip, .pinkyDIP, .pinkyTip] {
            mixed.landmarks[joint]?.position = mixed.landmarks[joint]!.position + Point2D(x: 0.3, y: 0)
        }
        XCTAssertEqual(tracker.update(candidates: [mixed], timestamp: t(2)).pointer.mode, .holding)
    }

    func testTheContinuingHandWinsOverAFarDetection() {
        var tracker = acquired()
        let near = Point2D(x: 0.51, y: 0.5)
        let far = Point2D(x: 0.15, y: 0.4)
        let pointer = tracker.update(candidates: [partial(far, t(2)), partial(near, t(2))], timestamp: t(2)).pointer
        XCTAssertEqual(pointer.mode, .partial)
        XCTAssertPointEqual(pointer.indexTip, near)
    }

    // MARK: Time limits and reacquisition

    func testShortDropoutIsBridgedWithoutANewAcquisition() {
        var tracker = acquired()
        let hold = tracker.update(candidates: [], timestamp: t(2)).pointer
        XCTAssertEqual(hold.mode, .holding)
        XCTAssertNil(hold.indexTip, "holding never repeats an old position")
        // The acquisition gate alone would need 2 new frames; the established hand continues now.
        let back = tracker.update(candidates: [full(Point2D(x: 0.5, y: 0.5), t(3))], timestamp: t(3))
        XCTAssertTrue(back.hands.isEmpty, "the strict gate itself is unchanged")
        XCTAssertEqual(back.pointer.mode, .full)
        XCTAssertFalse(back.pointer.startsSession)
    }

    func testDropoutLongerThanTheHoldTimeoutIsALoss() {
        var tracker = acquired()
        var modes: [PointerTrackingMode] = []
        for i in 2...8 { modes.append(tracker.update(candidates: [], timestamp: t(i)).pointer.mode) }
        // 0.15 s hold at 30 fps: frames 2…5 hold (≤ 4/30 s), frame 6 onward lost.
        XCTAssertEqual(modes, [.holding, .holding, .holding, .holding, .lost, .lost, .lost])
    }

    func testProlongedPartialTrackingEndsAfterTheLimit() {
        var tracker = acquired()
        let tip = Point2D(x: 0.5, y: 0.5)
        let lastFull = t(1)
        var i = 2
        while t(i) - lastFull < 2.9 {
            XCTAssertEqual(tracker.update(candidates: [partial(tip, t(i))], timestamp: t(i)).pointer.mode, .partial)
            i += 1
        }
        let late = lastFull + 3.1
        XCTAssertEqual(tracker.update(candidates: [partial(tip, late)], timestamp: late).pointer.mode, .lost)
    }

    func testIndexOnlyStreakIsLimited() {
        var tracker = acquired()
        let tip = Point2D(x: 0.5, y: 0.5)
        let start = t(2)
        var time = start
        while time - start < 0.9 {
            XCTAssertEqual(tracker.update(candidates: [indexOnly(tip, time)], timestamp: time).pointer.mode, .indexContinuity)
            time += dt
        }
        let late = start + 1.1
        XCTAssertEqual(tracker.update(candidates: [indexOnly(tip, late)], timestamp: late).pointer.mode, .lost)
    }

    func testAfterATimeoutOnlyAFullAcquisitionRestartsTracking() {
        var tracker = acquired()
        let tip = Point2D(x: 0.5, y: 0.5)
        _ = tracker.update(candidates: [], timestamp: 1.0) // long gap → lost
        XCTAssertEqual(tracker.mode, .lost)
        // The same partial hand that was acceptable before is now unknown.
        for i in 0..<10 {
            let time = 1.0 + Double(i + 1) * dt
            let pointer = tracker.update(candidates: [partial(tip, time)], timestamp: time).pointer
            XCTAssertEqual(pointer.mode, .lost)
            XCTAssertNil(pointer.indexTip, "no stale or partial position after a loss")
        }
        let a = 1.0 + 11 * dt
        let b = 1.0 + 12 * dt
        XCTAssertEqual(tracker.update(candidates: [full(tip, a)], timestamp: a).pointer.mode, .lost, "strict 2-frame gate")
        let again = tracker.update(candidates: [full(tip, b)], timestamp: b).pointer
        XCTAssertEqual(again.mode, .full)
        XCTAssertTrue(again.startsSession)
    }

    func testDisabledPeripheralTrackingIsPhase2Behavior() {
        var configuration = PointerTrackingConfiguration()
        configuration.enabled = false
        var tracker = acquired(configuration: configuration)
        XCTAssertEqual(tracker.update(candidates: [partial(Point2D(x: 0.5, y: 0.5), t(2))], timestamp: t(2)).pointer.mode, .lost)
        var other = acquired(configuration: configuration)
        XCTAssertEqual(other.update(candidates: [], timestamp: t(2)).pointer.mode, .lost, "no hold either")
    }

    func testSettingsControlPeripheralTracking() {
        var tracker = acquired()
        var settings = AirTrackSettings()
        settings.cursorPeripheralTracking = false
        tracker.apply(settings)
        XCTAssertFalse(tracker.configuration.enabled)
        XCTAssertEqual(tracker.update(candidates: [partial(Point2D(x: 0.5, y: 0.5), t(2))], timestamp: t(2)).pointer.mode, .lost)
    }

    func testResetForgetsTheHand() {
        var tracker = acquired()
        tracker.reset()
        XCTAssertEqual(tracker.update(candidates: [partial(Point2D(x: 0.5, y: 0.5), t(2))], timestamp: t(2)).pointer.mode, .lost)
    }

    func testSameInputsGiveSameDecisions() {
        func run() -> [PointerObservation] {
            var tracker = PointerTracker()
            var generator = SeededGenerator(seed: 9)
            var out: [PointerObservation] = []
            var tip = Point2D(x: 0.5, y: 0.5)
            for i in 0..<120 {
                tip = Rect2D.unit.clamp(tip + Point2D(x: Double.random(in: -0.02...0.02, using: &generator), y: Double.random(in: -0.02...0.02, using: &generator)))
                let candidates: [HandState]
                switch Int.random(in: 0..<4, using: &generator) {
                case 0: candidates = [full(tip, t(i))]
                case 1: candidates = [partial(tip, t(i))]
                case 2: candidates = [indexOnly(tip, t(i))]
                default: candidates = []
                }
                out.append(tracker.update(candidates: candidates, timestamp: t(i)).pointer)
            }
            return out
        }
        XCTAssertEqual(run(), run())
    }

    func testConfigurationIsSanitized() {
        var c = PointerTrackingConfiguration()
        c.minimumLandmarkConfidence = 0.7
        c.partialIndexConfidence = 0.2     // looser than a full hand: not allowed
        c.indexOnlyConfidence = .nan
        c.maximumSpeed = -1
        c.maximumStep = 9
        c.minimumStep = 1
        c.holdTimeout = 60
        c.maximumDegradedDuration = .infinity
        c.maximumIndexOnlyDuration = 50
        c.minimumPartialJoints = 0
        c.minimumCoherentFraction = 2
        let s = c.sanitized
        XCTAssertEqual(s.partialIndexConfidence, 0.7)
        XCTAssertGreaterThanOrEqual(s.indexOnlyConfidence, s.partialIndexConfidence)
        XCTAssertEqual(s.maximumSpeed, 0)
        XCTAssertEqual(s.maximumStep, 0.5)
        XCTAssertLessThanOrEqual(s.minimumStep, s.maximumStep)
        XCTAssertEqual(s.holdTimeout, 0.5)
        XCTAssertEqual(s.maximumDegradedDuration, PointerTrackingConfiguration().maximumDegradedDuration)
        XCTAssertLessThanOrEqual(s.maximumIndexOnlyDuration, s.maximumDegradedDuration)
        XCTAssertEqual(s.minimumPartialJoints, 2)
        XCTAssertEqual(s.minimumCoherentFraction, 1)
        // The tracker always holds a sanitized configuration.
        var tracker = PointerTracker()
        tracker.configuration = c
        XCTAssertEqual(tracker.configuration, s)
    }
}
