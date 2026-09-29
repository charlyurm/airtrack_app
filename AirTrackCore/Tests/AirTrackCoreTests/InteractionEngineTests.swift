import XCTest
@testable import AirTrackCore

/// PHASE 3A-1: the interaction engine in shadow mode (recognition, arbitration, lifecycle,
/// cursor policy). No test here expects a gesture action: 3A-1 emits none.
final class InteractionEngineTests: XCTestCase {
    private let dt = InteractionScenario.dt

    private func firstIntentFrame(_ frames: [InteractionFrame]) -> Int? {
        frames.firstIndex { $0.intent != nil }
    }

    // MARK: Scroll recognition (vertical only)

    func testTwoFingerVerticalMovementCommitsScroll() {
        var engine = InteractionEngine()
        let frames = InteractionScenario.moving(&engine, extended: TestPoses.twoFingers, step: Point2D(x: 0, y: 0.01), frames: 0..<8)
        XCTAssertEqual(firstIntentFrame(frames), 3, "pose stable at frame 1, 0.148 hand scales of travel at frame 3")
        XCTAssertEqual(frames[3].intent, .twoFingerScroll)
        XCTAssertEqual(frames[3].lifecycle, .confirmed)
        XCTAssertEqual(frames[4].lifecycle, .active)
        XCTAssertEqual(frames[1].lifecycle, .candidate)
    }

    func testOpenHandVerticalMovementCommitsScroll() {
        var engine = InteractionEngine()
        let frames = InteractionScenario.moving(&engine, extended: TestPoses.fourFingers, thumb: .extended, step: Point2D(x: 0, y: -0.01), frames: 0..<8)
        XCTAssertEqual(frames[3].intent, .openHandScroll)
    }

    func testHorizontalMovementNeverCommits() {
        var engine = InteractionEngine()
        let frames = InteractionScenario.moving(&engine, extended: TestPoses.twoFingers, from: Point2D(x: 0.3, y: 0.5), step: Point2D(x: 0.01, y: 0), frames: 0..<14)
        XCTAssertNil(firstIntentFrame(frames))
        XCTAssertEqual(frames.last?.candidate?.axis, .horizontal)
    }

    func testDiagonalMovementIsAmbiguousAndNeverCommits() {
        var engine = InteractionEngine()
        let frames = InteractionScenario.moving(&engine, extended: TestPoses.twoFingers, from: Point2D(x: 0.35, y: 0.35), step: Point2D(x: 0.01, y: 0.01), frames: 0..<14)
        XCTAssertNil(firstIntentFrame(frames))
        XCTAssertEqual(frames.last?.candidate?.axis, .ambiguous)
    }

    func testMovementBelowThresholdNeverCommits() {
        var engine = InteractionEngine()
        let frames = InteractionScenario.moving(&engine, extended: TestPoses.twoFingers, step: Point2D(x: 0, y: 0.001), frames: 0..<12)
        XCTAssertNil(firstIntentFrame(frames))
    }

    func testSlowMovementCommitsLaterThanFastMovement() throws {
        var slow = InteractionEngine()
        var fast = InteractionEngine()
        let slowFrames = InteractionScenario.moving(&slow, extended: TestPoses.twoFingers, step: Point2D(x: 0, y: 0.002), frames: 0..<15)
        let fastFrames = InteractionScenario.moving(&fast, extended: TestPoses.twoFingers, step: Point2D(x: 0, y: 0.03), frames: 0..<15)
        let slowCommit = try XCTUnwrap(firstIntentFrame(slowFrames))
        let fastCommit = try XCTUnwrap(firstIntentFrame(fastFrames))
        XCTAssertEqual(fastCommit, 2)
        XCTAssertEqual(slowCommit, 10)
    }

    func testCommitIsScaleInvariant() {
        for scale in [0.5, 1, 2] {
            var engine = InteractionEngine()
            // 0.074 hand scales per frame, whatever the hand's size in the image.
            let frames = InteractionScenario.moving(&engine, extended: TestPoses.twoFingers, from: Point2D(x: 0.5, y: 0.35),
                                                    step: Point2D(x: 0, y: 0.01 * scale), frames: 0..<8, scale: scale)
            XCTAssertEqual(firstIntentFrame(frames), 3, "scale \(scale)")
        }
    }

    func testPointingNeverProducesACandidate() {
        var engine = InteractionEngine()
        let frames = InteractionScenario.moving(&engine, extended: TestPoses.pointing, step: Point2D(x: 0, y: 0.01), frames: 0..<10)
        XCTAssertTrue(frames.allSatisfy { $0.candidate == nil && $0.intent == nil && $0.cursorPolicy == .follow })
        XCTAssertEqual(frames.last?.pose, .pointing)
    }

    func testPinchAndFourFingersAreRecognizedButDoNothingYet() {
        var engine = InteractionEngine()
        let pinch = InteractionScenario.moving(&engine, extended: TestPoses.pointing, thumb: .pinching, step: Point2D(x: 0, y: 0.01), frames: 0..<6)
        XCTAssertEqual(pinch.last?.pose, .pinch)
        XCTAssertTrue(pinch.allSatisfy { $0.intent == nil && $0.cursorPolicy == .follow })
        var engine2 = InteractionEngine()
        let four = InteractionScenario.moving(&engine2, extended: TestPoses.fourFingers, thumb: .folded, step: Point2D(x: 0.01, y: 0), frames: 0..<6)
        XCTAssertEqual(four.last?.pose, .fourFinger)
        XCTAssertTrue(four.allSatisfy { $0.intent == nil })
    }

    // MARK: Cursor policy (advisory in 3A-1)

    func testStableScrollCandidateFreezesTheCursorAfterTheDelay() {
        var engine = InteractionEngine()
        let frames = InteractionScenario.moving(&engine, extended: TestPoses.twoFingers, step: .zero, frames: 0..<7)
        XCTAssertEqual(frames.map(\.cursorPolicy), [.follow, .follow, .follow, .follow, .frozen, .frozen, .frozen])
    }

    // MARK: Tracking continuity (PointerTracker is the source of truth)

    func testHoldSuspendsRecoveryResumesLostReleases() {
        var engine = InteractionEngine()
        var frames = InteractionScenario.moving(&engine, extended: TestPoses.twoFingers, step: Point2D(x: 0, y: 0.01), frames: 0..<5)
        XCTAssertEqual(frames.last?.lifecycle, .active)
        let hold = InteractionScenario.feed(&engine, nil, mode: .holding, at: 5 * dt)
        XCTAssertEqual(hold.lifecycle, .suspended)
        XCTAssertEqual(hold.intent, .twoFingerScroll)
        XCTAssertEqual(hold.cursorPolicy, .frozen)
        frames = InteractionScenario.moving(&engine, extended: TestPoses.twoFingers, from: Point2D(x: 0.5, y: 0.46), step: Point2D(x: 0, y: 0.01), frames: 6..<7)
        XCTAssertEqual(frames.last?.lifecycle, .active, "recovered")
        let lost = InteractionScenario.feed(&engine, nil, mode: .lost, at: 7 * dt)
        XCTAssertEqual(lost.released, .trackingLost)
        XCTAssertNil(lost.intent)
        XCTAssertEqual(lost.cursorPolicy, .follow)
        XCTAssertEqual(InteractionScenario.feed(&engine, nil, mode: .lost, at: 8 * dt).lifecycle, .idle)
    }

    func testDegradedTrackingReleasesAndNeverStartsGestures() {
        var engine = InteractionEngine()
        _ = InteractionScenario.moving(&engine, extended: TestPoses.twoFingers, step: Point2D(x: 0, y: 0.01), frames: 0..<5)
        let partial = InteractionScenario.feed(&engine, TestPoses.hand(extended: TestPoses.twoFingers, at: 5 * dt), mode: .partial, at: 5 * dt)
        XCTAssertEqual(partial.released, .trackingDegraded)
        for i in 6..<20 {
            let t = Double(i) * dt
            let hand = TestPoses.hand(extended: TestPoses.twoFingers, at: t, center: Point2D(x: 0.5, y: 0.3 + 0.01 * Double(i)))
            let frame = InteractionScenario.feed(&engine, hand, mode: i.isMultiple(of: 2) ? .partial : .indexContinuity, at: t)
            XCTAssertNil(frame.candidate)
            XCTAssertNil(frame.intent)
            XCTAssertEqual(frame.cursorPolicy, .follow)
        }
    }

    func testUnknownOrMissingHandNeverActivates() {
        var engine = InteractionEngine()
        for i in 0..<15 {
            let t = Double(i) * dt
            // FULL mode reported but no hand to measure (defensive): nothing happens.
            let frame = InteractionScenario.feed(&engine, nil, mode: .full, at: t)
            XCTAssertNil(frame.candidate)
            XCTAssertEqual(frame.availability, .degraded)
        }
    }

    func testStaleFramesNeverCommit() {
        var engine = InteractionEngine()
        _ = InteractionScenario.moving(&engine, extended: TestPoses.twoFingers, step: .zero, frames: 0..<2)
        for k in 0..<10 {
            // Same timestamp again and again, with a hand that "moves": not new information.
            let hand = TestPoses.hand(extended: TestPoses.twoFingers, at: dt, center: Point2D(x: 0.5, y: 0.4 + 0.02 * Double(k)))
            let frame = InteractionScenario.feed(&engine, hand, at: dt)
            XCTAssertNil(frame.intent)
        }
    }

    // MARK: Transitions without a neutral pose

    func testCursorScrollCursorPinchScrollWithoutNeutralPose() {
        var engine = InteractionEngine()
        var t = 0
        func run(_ fingers: FingerSet, _ thumb: TestPoses.Thumb = .folded, dy: Double, count: Int) -> [InteractionFrame] {
            defer { t += count }
            return InteractionScenario.moving(&engine, extended: fingers, thumb: thumb, from: Point2D(x: 0.5, y: 0.3),
                                              step: Point2D(x: 0, y: dy), frames: t..<(t + count))
        }
        XCTAssertNil(firstIntentFrame(run(TestPoses.pointing, dy: 0.01, count: 4)))
        XCTAssertNotNil(firstIntentFrame(run(TestPoses.twoFingers, dy: 0.01, count: 6)))
        let back = run(TestPoses.pointing, dy: 0, count: 4)
        XCTAssertTrue(back.contains { $0.released == .gestureEnded })
        XCTAssertEqual(back.last?.intent, nil)
        XCTAssertEqual(back.last?.cursorPolicy, .follow)
        XCTAssertEqual(run(TestPoses.pointing, .pinching, dy: 0, count: 4).last?.pose, .pinch)
        XCTAssertNotNil(firstIntentFrame(run(TestPoses.twoFingers, dy: 0.01, count: 6)), "scroll again, no reset needed")
    }

    // MARK: Shadow mode safety

    func testShadowEngineNeverEmitsActions() {
        var engine = InteractionEngine()
        var generator = SeededGenerator(seed: 7)
        let kinds: [(FingerSet, TestPoses.Thumb)] = [
            (TestPoses.pointing, .folded), (TestPoses.twoFingers, .folded), (TestPoses.fourFingers, .extended),
            (TestPoses.fourFingers, .folded), (TestPoses.pointing, .pinching),
        ]
        var center = Point2D(x: 0.5, y: 0.5)
        for i in 0..<300 {
            let (fingers, thumb) = kinds[(i / 12) % kinds.count]
            center = Rect2D(x: 0.3, y: 0.3, width: 0.4, height: 0.4).clamp(center + Point2D(
                x: Double.random(in: -0.02...0.02, using: &generator), y: Double.random(in: -0.03...0.03, using: &generator)))
            let modes: [PointerTrackingMode] = [.full, .full, .full, .holding, .partial, .lost]
            let mode = modes[Int.random(in: 0..<modes.count, using: &generator)]
            let hand = TestPoses.hand(extended: fingers, thumb: thumb, at: Double(i) * dt, center: center)
            let frame = InteractionScenario.feed(&engine, hand, mode: mode, at: Double(i) * dt)
            XCTAssertTrue(frame.actions.isEmpty)
        }
    }

    func testCancelAndResetClearTheInteraction() {
        var engine = InteractionEngine()
        _ = InteractionScenario.moving(&engine, extended: TestPoses.twoFingers, step: Point2D(x: 0, y: 0.01), frames: 0..<5)
        XCTAssertEqual(engine.arbiter.owner, .twoFingerScroll)
        _ = engine.cancel()
        XCTAssertNil(engine.arbiter.owner)
        engine.reset()
        XCTAssertEqual(engine.poseClassifier.stablePose, .unknown)
        XCTAssertEqual(engine.history.count, 0)
    }

    func testSameInputGivesSameFrames() {
        func run() -> [InteractionFrame] {
            var engine = InteractionEngine()
            return InteractionScenario.moving(&engine, extended: TestPoses.twoFingers, step: Point2D(x: 0.001, y: 0.012), frames: 0..<20)
        }
        XCTAssertEqual(run(), run())
    }
}
