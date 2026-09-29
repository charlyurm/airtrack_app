import XCTest
@testable import AirTrackCore

/// PHASE 3A-2: live scroll through the whole interaction engine (recognition → arbiter →
/// ScrollController → actions), cursor policy, inertia, tracking loss and output safety.
final class ScrollInteractionTests: XCTestCase {
    /// A continuous hand: time and position carry over between pose changes.
    private struct Session {
        var engine = InteractionEngine()
        var frame = 0
        var center = Point2D(x: 0.5, y: 0.3)

        mutating func run(
            _ fingers: FingerSet,
            _ thumb: TestPoses.Thumb = .folded,
            step: Point2D = .zero,
            count: Int,
            mode: PointerTrackingMode = .full,
            live: Bool = true
        ) -> [InteractionFrame] {
            (0..<count).map { _ in
                let t = Double(frame) * InteractionScenario.dt
                frame += 1
                center = center + step
                let hand = TestPoses.hand(extended: fingers, thumb: thumb, at: t, center: center)
                return InteractionScenario.feed(&engine, mode.providesPointer ? hand : nil, mode: mode, at: t, live: live)
            }
        }
    }

    private let down = Point2D(x: 0, y: 0.01)
    private func scrolls(_ frames: [InteractionFrame]) -> [ScrollAction] { InteractionScenario.scrolls(frames) }
    private func momentum(_ actions: [ScrollAction]) -> [ScrollAction] { actions.filter { $0.momentum != .none } }

    // MARK: Recognition → live scroll

    func testTwoFingerVerticalScrollIsLiveAndFollowsTheHand() {
        var s = Session()
        let frames = s.run(TestPoses.twoFingers, step: down, count: 10)
        let actions = scrolls(frames)
        XCTAssertEqual(scrolls([frames[3]]).first?.phase, .began, "commit frame")
        XCTAssertTrue(scrolls(Array(frames[0..<3])).isEmpty, "nothing before the commit")
        XCTAssertTrue(actions.dropFirst().allSatisfy { $0.phase == .changed })
        XCTAssertTrue(actions.allSatisfy { $0.delta > 0 }, "hand down → content down")
        XCTAssertTrue(frames[3...].allSatisfy { $0.cursorPolicy == .frozen && $0.liveOutput })
    }

    func testOpenHandVerticalScroll() {
        var s = Session()
        s.center = Point2D(x: 0.5, y: 0.6)
        let actions = scrolls(s.run(TestPoses.fourFingers, .extended, step: Point2D(x: 0, y: -0.01), count: 10))
        XCTAssertFalse(actions.isEmpty)
        XCTAssertTrue(actions.allSatisfy { $0.delta < 0 }, "hand up → content up")
    }

    func testHorizontalAndDiagonalMovementNeverScroll() {
        var horizontal = Session()
        horizontal.center = Point2D(x: 0.3, y: 0.4)
        XCTAssertTrue(scrolls(horizontal.run(TestPoses.twoFingers, step: Point2D(x: 0.01, y: 0), count: 14)).isEmpty)
        var diagonal = Session()
        diagonal.center = Point2D(x: 0.3, y: 0.3)
        XCTAssertTrue(scrolls(diagonal.run(TestPoses.twoFingers, step: Point2D(x: 0.01, y: 0.01), count: 14)).isEmpty)
    }

    func testThumbOnMiddleTipNeverScrolls() {
        var s = Session()
        XCTAssertTrue(scrolls(s.run(TestPoses.twoFingers, .touchingMiddle, step: down, count: 12)).isEmpty,
                      "future right-click relation is not the scroll pose")
    }

    func testFasterHandScrollsMore() {
        var slow = Session()
        var fast = Session()
        let a = scrolls(slow.run(TestPoses.twoFingers, step: Point2D(x: 0, y: 0.004), count: 14)).map(\.delta).reduce(0, +)
        let b = scrolls(fast.run(TestPoses.twoFingers, step: Point2D(x: 0, y: 0.015), count: 14)).map(\.delta).reduce(0, +)
        XCTAssertGreaterThan(a, 0)
        XCTAssertGreaterThan(b, a * 3)
    }

    // MARK: Axis lock

    func testHorizontalNoiseDoesNotRedirectAnActiveScroll() {
        var s = Session()
        var frames = s.run(TestPoses.twoFingers, step: down, count: 5)
        for i in 0..<10 {
            frames += s.run(TestPoses.twoFingers, step: Point2D(x: i.isMultiple(of: 2) ? 0.02 : -0.02, y: 0.01), count: 1)
        }
        let actions = scrolls(frames)
        XCTAssertTrue(actions.allSatisfy { $0.delta > 0 })
        XCTAssertEqual(frames.last?.intent, .twoFingerScroll)
    }

    func testPurelyHorizontalMotionAfterCommitDoesNotScrollSideways() {
        var s = Session()
        _ = s.run(TestPoses.twoFingers, step: down, count: 5)
        let frames = s.run(TestPoses.twoFingers, step: Point2D(x: 0.01, y: 0), count: 10)
        let actions = scrolls(frames)
        XCTAssertTrue(actions.allSatisfy { $0.delta >= 0 }, "only the vertical component is used")
        XCTAssertLessThan(actions.map(\.delta).reduce(0, +), 20, "only the fading vertical speed")
        XCTAssertEqual(frames.last?.intent, .twoFingerScroll, "still the same scroll")
    }

    // MARK: Stop, release, inertia

    func testStoppingWhileHoldingThePoseStopsWithoutInertia() {
        var s = Session()
        _ = s.run(TestPoses.twoFingers, step: down, count: 6)
        let still = s.run(TestPoses.twoFingers, count: 10)
        XCTAssertTrue(scrolls(Array(still.suffix(5))).isEmpty, "a still hand scrolls nothing")
        let after = scrolls(s.run(TestPoses.pointing, count: 15))
        XCTAssertEqual(after.first?.phase, .ended)
        XCTAssertTrue(momentum(after).isEmpty, "no artificial momentum after a pause")
    }

    func testReleaseWhileMovingStartsBoundedInertiaAndTheCursorReturns() {
        var s = Session()
        _ = s.run(TestPoses.twoFingers, step: down, count: 8)
        let frames = s.run(TestPoses.pointing, step: Point2D(x: 0.002, y: 0), count: 45)
        let actions = scrolls(frames)
        XCTAssertEqual(actions.first, ScrollAction(delta: 0, phase: .ended))
        let coast = momentum(actions)
        XCTAssertEqual(coast.first?.momentum, .began)
        XCTAssertEqual(coast.last?.momentum, .ended)
        XCTAssertTrue(coast.allSatisfy { $0.delta >= 0 })
        let config = ScrollConfiguration()
        XCTAssertLessThanOrEqual(Double(coast.map(\.delta).reduce(0, +)), config.inertiaDistanceBound)
        // First pointing frame: the scroll still owns the hand (one missing frame is tolerated).
        XCTAssertEqual(frames.first?.cursorPolicy, .frozen)
        XCTAssertTrue(frames.dropFirst().allSatisfy { $0.cursorPolicy == .follow }, "the cursor is back while it coasts")
        XCTAssertEqual(frames.last?.lifecycle, .idle)
        XCTAssertTrue(frames.contains { $0.lifecycle == .releasing && $0.scrollState == .momentum })
    }

    func testNewGestureCancelsInertia() {
        var s = Session()
        _ = s.run(TestPoses.twoFingers, step: down, count: 8)
        _ = s.run(TestPoses.pointing, count: 4) // released, coasting
        XCTAssertEqual(s.engine.scroll.state, .momentum)
        let pinch = scrolls(s.run(TestPoses.pointing, .pinching, count: 6))
        XCTAssertEqual(pinch.last, ScrollAction(delta: 0, phase: nil, momentum: .ended))
        XCTAssertEqual(s.engine.scroll.state, .idle)
        XCTAssertTrue(scrolls(s.run(TestPoses.pointing, .pinching, count: 10)).isEmpty)
    }

    func testCursorPolicyBeforeDuringAndAfterScroll() {
        var s = Session()
        XCTAssertTrue(s.run(TestPoses.pointing, step: down, count: 5).allSatisfy { $0.cursorPolicy == .follow })
        let scroll = s.run(TestPoses.twoFingers, step: down, count: 8)
        XCTAssertEqual(scroll.last?.cursorPolicy, .frozen)
        let back = s.run(TestPoses.pointing, count: 4)
        XCTAssertEqual(back.last?.cursorPolicy, .follow)
    }

    // MARK: Tracking continuity

    func testHoldSuspendsAndRecoveryContinuesTheSameScroll() {
        var s = Session()
        _ = s.run(TestPoses.twoFingers, step: down, count: 6)
        let hold = s.run(TestPoses.twoFingers, step: down, count: 2, mode: .holding)
        XCTAssertTrue(scrolls(hold).isEmpty, "no new deltas without fresh landmarks")
        XCTAssertTrue(hold.allSatisfy { $0.lifecycle == .suspended && $0.cursorPolicy == .frozen })
        let back = scrolls(s.run(TestPoses.twoFingers, step: down, count: 3))
        XCTAssertFalse(back.isEmpty)
        XCTAssertTrue(back.allSatisfy { $0.phase == .changed && $0.delta > 0 }, "same scroll, no new began")
    }

    func testLostEndsTheScrollWithoutInertiaAndNothingStaleFollows() {
        var s = Session()
        _ = s.run(TestPoses.twoFingers, step: down, count: 6)
        let lost = scrolls(s.run(TestPoses.twoFingers, step: down, count: 30, mode: .lost))
        XCTAssertEqual(lost, [ScrollAction(delta: 0, phase: .ended)])
    }

    func testPartialViewKeepsScrollingWithRealMotion() {
        var s = Session()
        _ = s.run(TestPoses.twoFingers, step: down, count: 6)
        // Moving down, the wrist leaves the image: PARTIAL tracking, the scroll goes on.
        var frames: [InteractionFrame] = []
        for _ in 0..<6 {
            let t = Double(s.frame) * InteractionScenario.dt
            s.frame += 1
            s.center = s.center + down
            let hand = TestPoses.hand(extended: TestPoses.twoFingers, at: t, center: s.center, omit: [.wrist])
            frames.append(InteractionScenario.feed(&s.engine, hand, mode: .partial, at: t, live: true))
        }
        let actions = scrolls(frames)
        XCTAssertEqual(actions.count, 6)
        XCTAssertTrue(actions.allSatisfy { $0.phase == .changed && $0.delta > 0 })
    }

    // MARK: Output safety

    func testSwitchingOutputOffClosesTheScrollImmediately() {
        var s = Session()
        _ = s.run(TestPoses.twoFingers, step: down, count: 6)
        let off = s.run(TestPoses.twoFingers, step: down, count: 3, live: false)
        XCTAssertEqual(scrolls(off), [ScrollAction(delta: 0, phase: .ended)])
        // Back on mid-gesture: that gesture stays observed only (no phase out of nowhere).
        XCTAssertTrue(scrolls(s.run(TestPoses.twoFingers, step: down, count: 3)).isEmpty)
        XCTAssertTrue(scrolls(s.run(TestPoses.pointing, count: 3)).isEmpty)
        let again = scrolls(s.run(TestPoses.twoFingers, step: down, count: 6))
        XCTAssertEqual(again.first?.phase, .began, "a new scroll starts cleanly")
    }

    func testCancelClosesAnOpenScrollOrInertia() {
        var scrolling = Session()
        _ = scrolling.run(TestPoses.twoFingers, step: down, count: 6)
        XCTAssertEqual(scrolling.engine.cancel(), [.scroll(ScrollAction(delta: 0, phase: .ended))])
        XCTAssertTrue(scrolls(scrolling.run(TestPoses.twoFingers, step: down, count: 2)).isEmpty, "nothing stale")

        var coasting = Session()
        _ = coasting.run(TestPoses.twoFingers, step: down, count: 8)
        _ = coasting.run(TestPoses.pointing, count: 4)
        XCTAssertEqual(coasting.engine.cancel(), [.scroll(ScrollAction(delta: 0, phase: nil, momentum: .ended))])
        XCTAssertEqual(coasting.engine.cancel(), [], "idempotent")
    }

    func testShadowModeRecognizesButNeverScrolls() {
        var s = Session()
        let frames = s.run(TestPoses.twoFingers, step: down, count: 10, live: false)
        XCTAssertEqual(frames.last?.intent, .twoFingerScroll)
        XCTAssertTrue(frames.allSatisfy { $0.actions.isEmpty && !$0.liveOutput })
    }

    func testSameInputGivesSameScroll() {
        func run() -> [ScrollAction] {
            var s = Session()
            return scrolls(s.run(TestPoses.twoFingers, step: Point2D(x: 0.001, y: 0.012), count: 12)
                + s.run(TestPoses.pointing, count: 40))
        }
        XCTAssertEqual(run(), run())
    }
}
