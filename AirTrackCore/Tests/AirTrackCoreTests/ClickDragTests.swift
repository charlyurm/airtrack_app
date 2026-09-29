import XCTest
@testable import AirTrackCore

/// PHASE 3B: left click and drag through the whole interaction engine (pinch recognizer →
/// arbiter → PinchIntentController → actions), cursor ownership, tracking and safety.
final class ClickDragTests: XCTestCase {
    private let threshold = PinchIntentConfiguration().dragDistance
    private let right = Point2D(x: 0.01, y: 0)

    /// Confirmed pinch, then moving until the drag commits. Returns the moving frames.
    private func dragging(_ d: inout HandDriver, move: Point2D = Point2D(x: 0.01, y: 0), count: Int = 6) -> [InteractionFrame] {
        _ = d.pinch(count: 2)
        let frames = d.pinch(count: count, move: move)
        XCTAssertEqual(frames.dragBegins, 1, "setup: the drag committed")
        return frames
    }

    // MARK: Click

    func testQuickPinchClicksExactlyOnce() {
        var d = HandDriver()
        let frames = d.pinch(count: 2) + d.open(count: 2)
        XCTAssertEqual(frames.buttonActions, [.leftClick])
        XCTAssertEqual(frames[3].clicks, 1, "on the confirmed release")
        XCTAssertEqual(frames[3].pinch.outcome, .click)
        XCTAssertEqual(d.engine.pinchIntent.lastClick?.time ?? -1, 3 * InteractionScenario.dt, accuracy: 1e-9, "timing kept for a future double click")
        XCTAssertTrue(d.open(count: 5).buttonActions.isEmpty, "no duplicate click")
    }

    func testNormalPinchHoldThenReleaseClicks() {
        var d = HandDriver()
        XCTAssertEqual((d.pinch(count: 12) + d.open(count: 3)).buttonActions, [.leftClick])
    }

    func testVeryLongStillPinchIsNotAClick() {
        var d = HandDriver()
        let frames = d.pinch(count: 40) + d.open(count: 3)
        XCTAssertTrue(frames.buttonActions.isEmpty, "held 1.3 s: intent unclear, no action")
        XCTAssertEqual(frames.last { $0.pinch.outcome != nil }?.pinch.outcome, .noAction)
    }

    func testTinyMovementStillClicks() {
        var d = HandDriver()
        let frames = d.pinch(count: 2) + d.pinch(count: 10, move: Point2D(x: 0.0015, y: 0.001)) + d.open(count: 2)
        XCTAssertLessThan(frames[11].pinch.movement, threshold)
        XCTAssertEqual(frames.buttonActions, [.leftClick], "natural jitter is not a drag")
    }

    func testRepeatedPinchesClickOncePerPinchWithoutNeutralPose() {
        var d = HandDriver()
        var frames: [InteractionFrame] = []
        for _ in 0..<5 { frames += d.pinch(count: 3) + d.open(count: 3) }
        XCTAssertEqual(frames.buttonActions, Array(repeating: .leftClick, count: 5))
    }

    func testClickAnywhereInTheFrameFreezesTheCursorWhilePending() {
        for center in [Point2D(x: 0.3, y: 0.35), Point2D(x: 0.7, y: 0.4), Point2D(x: 0.5, y: 0.65)] {
            var d = HandDriver()
            d.center = center
            let before = d.open(count: 3)
            let pending = d.pinch(count: 3)
            let after = d.open(count: 4)
            XCTAssertTrue(before.allSatisfy { $0.appliedCursorPolicy == .follow }, "\(center)")
            XCTAssertTrue(pending.dropFirst().allSatisfy { $0.appliedCursorPolicy == .frozen },
                          "the click lands where the cursor was when the pinch was confirmed")
            XCTAssertEqual((before + pending + after).buttonActions, [.leftClick], "\(center)")
            XCTAssertEqual(after.last?.appliedCursorPolicy, .follow, "cursor → pinch → click → cursor")
        }
    }

    func testClickRightAfterMovingTheCursor() {
        var d = HandDriver()
        d.center = Point2D(x: 0.35, y: 0.5)
        let moving = d.open(count: 10, move: Point2D(x: 0.012, y: 0.004))
        XCTAssertTrue(moving.allSatisfy { $0.appliedCursorPolicy == .follow && $0.actions.isEmpty })
        XCTAssertEqual((d.pinch(count: 3) + d.open(count: 2)).buttonActions, [.leftClick])
    }

    // MARK: Drag

    func testHoldAndMoveCommitsOneDragAtTheThreshold() throws {
        var d = HandDriver()
        let frames = dragging(&d)
        let begin = try XCTUnwrap(frames.firstIndex { $0.beginsDrag })
        XCTAssertGreaterThanOrEqual(frames[begin].pinch.movement, threshold)
        if begin > 0 { XCTAssertLessThan(frames[begin - 1].pinch.movement, threshold) }
        XCTAssertTrue(frames[..<begin].allSatisfy { $0.appliedCursorPolicy == .frozen && $0.actions.isEmpty })
        XCTAssertTrue(frames[begin...].allSatisfy {
            $0.appliedCursorPolicy == .drag && $0.pinch.buttonDown && $0.pinch.dragFollowsIndex && $0.pinch.phase == .dragging
        })
        let release = d.open(count: 3)
        XCTAssertEqual((frames + release).buttonActions, [.beginDrag, .endDrag], "mouseDown, mouseUp, never a click")
        XCTAssertEqual(release[1].pinch.outcome, .dragEnded)
        XCTAssertEqual(release.last?.appliedCursorPolicy, .follow)
    }

    func testMovementBelowTheThresholdNeverDrags() {
        var d = HandDriver()
        let frames = d.pinch(count: 2) + d.pinch(count: 12, move: Point2D(x: 0.0008, y: 0.0008))
        XCTAssertEqual(frames.dragBegins, 0)
        XCTAssertTrue(frames.dropFirst().allSatisfy { $0.appliedCursorPolicy == .frozen })
    }

    func testJitterBackAndForthIsNotADrag() {
        var d = HandDriver()
        var frames = d.pinch(count: 2)
        for i in 0..<12 { frames += d.pinch(count: 1, move: Point2D(x: i.isMultiple(of: 2) ? 0.012 : -0.012, y: 0)) }
        frames += d.open(count: 2)
        XCTAssertEqual(frames.buttonActions, [.leftClick], "net displacement, not path length")
    }

    func testSlowNormalAndFastDrags() throws {
        var commits: [Int] = []
        for speed in [0.002, 0.01, 0.03] {
            var d = HandDriver()
            d.center = Point2D(x: 0.3, y: 0.5)
            _ = d.pinch(count: 2)
            let frames = d.pinch(count: 14, move: Point2D(x: speed, y: 0)) + d.open(count: 2)
            XCTAssertEqual(frames.buttonActions, [.beginDrag, .endDrag], "speed \(speed)")
            commits.append(try XCTUnwrap(frames.firstIndex { $0.beginsDrag }))
        }
        XCTAssertEqual(commits, commits.sorted(by: >), "faster movement commits sooner")
        XCTAssertEqual(commits.last, 0, "a fast, clear movement commits on its first frame")
    }

    func testHorizontalVerticalAndDiagonalDrags() {
        for move in [Point2D(x: 0.01, y: 0), Point2D(x: -0.01, y: 0), Point2D(x: 0, y: 0.01), Point2D(x: 0, y: -0.01), Point2D(x: 0.007, y: -0.007)] {
            var d = HandDriver()
            _ = d.pinch(count: 2)
            let frames = d.pinch(count: 8, move: move) + d.open(count: 2)
            XCTAssertEqual(frames.buttonActions, [.beginDrag, .endDrag], "\(move)")
            XCTAssertTrue(InteractionScenario.scrolls(frames).isEmpty, "a vertical drag is not a scroll")
        }
    }

    func testDragReturningToItsStartNeverClicks() {
        var d = HandDriver()
        _ = d.pinch(count: 2)
        let frames = d.pinch(count: 5, move: right) + d.pinch(count: 5, move: Point2D(x: -0.01, y: 0)) + d.open(count: 2)
        XCTAssertEqual(frames.buttonActions, [.beginDrag, .endDrag], "once dragged, the pinch can only end the drag")
    }

    func testUncertainPinchPausesTheDragWithoutReleasing() {
        var d = HandDriver()
        _ = dragging(&d)
        let blip = d.open(count: 1)[0]
        XCTAssertTrue(blip.actions.isEmpty)
        XCTAssertEqual(blip.appliedCursorPolicy, .drag)
        XCTAssertFalse(blip.pinch.dragFollowsIndex, "uncertain: the dragged object stays, nothing extrapolated")
        XCTAssertTrue(d.pinch(count: 2, move: right).allSatisfy { $0.pinch.dragFollowsIndex && $0.actions.isEmpty })
    }

    // MARK: Tracking

    func testBriefHoldSuspendsAndRecoveryContinuesTheSameDrag() {
        var d = HandDriver()
        _ = dragging(&d)
        let hold = d.run(count: 2, mode: .holding)
        XCTAssertTrue(hold.allSatisfy {
            $0.lifecycle == .suspended && $0.actions.isEmpty && $0.appliedCursorPolicy == .drag && !$0.pinch.dragFollowsIndex
        })
        let back = d.pinch(count: 3, move: right)
        XCTAssertTrue(back.allSatisfy { $0.lifecycle == .active && $0.pinch.dragFollowsIndex && $0.actions.isEmpty }, "no second mouseDown")
        XCTAssertEqual(d.open(count: 2).buttonActions, [.endDrag])
    }

    func testProlongedHoldReleasesTheButtonOnce() {
        var d = HandDriver()
        _ = dragging(&d)
        let hold = d.run(count: 20, mode: .holding)
        XCTAssertEqual(hold.buttonActions, [.endDrag])
        XCTAssertEqual(hold.first { $0.endsDrag }?.released, .recognitionTimeout)
        XCTAssertLessThanOrEqual(hold.firstIndex { $0.endsDrag } ?? 99, 8, "bounded by the maintenance grace (0.25 s)")
        XCTAssertEqual(hold.last?.appliedCursorPolicy, .follow)
    }

    func testLostReleasesTheButtonImmediately() {
        var d = HandDriver()
        _ = dragging(&d)
        let lost = d.run(count: 10, mode: .lost)
        XCTAssertEqual(lost[0].actions, [.endDrag])
        XCTAssertEqual(lost[0].released, .trackingLost)
        XCTAssertTrue(lost.dropFirst().allSatisfy { $0.actions.isEmpty })
    }

    func testTrackingLossCancelsAPendingClick() {
        var d = HandDriver()
        _ = d.pinch(count: 3)
        let lost = d.run(count: 2, mode: .lost)
        let after = d.open(count: 3) + d.pinch(count: 1) + d.open(count: 2)
        XCTAssertTrue((lost + after).buttonActions.isEmpty, "the hand disappearing is never a release")
    }

    func testHoldDuringAPendingClickCancelsTheClick() {
        var d = HandDriver()
        _ = d.pinch(count: 3)
        _ = d.run(count: 1, mode: .holding)
        let frames = d.pinch(count: 2) + d.open(count: 2)
        XCTAssertTrue(frames.buttonActions.isEmpty, "release seen only after a tracking gap: no click")
        XCTAssertEqual(frames.last?.pinch.outcome, .noAction)
    }

    func testStaleFramesNeitherMoveNorClick() {
        var d = HandDriver()
        _ = d.pinch(count: 2)
        let t = d.time - InteractionScenario.dt // the timestamp of the last processed frame
        var stale: [InteractionFrame] = []
        for k in 0..<10 {
            // Same timestamp again and again with a hand that "moves": not new information.
            let hand = TestPoses.hand(extended: TestPoses.pointing, thumb: .pinching, at: t, center: Point2D(x: 0.5 + 0.02 * Double(k), y: 0.5))
            stale.append(d.engine.update(pointer: InteractionScenario.pointer(.full, hand: hand, at: t), trackedHand: hand, outputs: .all))
        }
        XCTAssertEqual(stale.dragBegins, 0)
        XCTAssertTrue(stale.allSatisfy { $0.availability == .gap && $0.pinch.movement == 0 })
        XCTAssertTrue((d.pinch(count: 1) + d.open(count: 2)).buttonActions.isEmpty, "the pending click was interrupted")
    }

    func testPartialViewKeepsTheDragFollowingButNeverStartsOne() {
        var d = HandDriver()
        _ = dragging(&d)
        let partial = d.run(move: right, count: 5, mode: .partial, omit: [.wrist])
        XCTAssertTrue(partial.allSatisfy { $0.intent == .pinch && $0.pinch.dragFollowsIndex && $0.actions.isEmpty })
        XCTAssertEqual(d.open(count: 2).buttonActions, [.endDrag])
    }

    // MARK: Pause / Accessibility / camera / shutdown (all reach the engine as cancel())

    func testCancelDuringDragReleasesTheButtonExactlyOnce() {
        var d = HandDriver()
        _ = dragging(&d)
        XCTAssertEqual(d.engine.cancel(), [.endDrag])
        XCTAssertEqual(d.engine.cancel(), [], "idempotent: no mouseUp without mouseDown")
        let after = d.pinch(count: 4, move: right) + d.open(count: 3)
        XCTAssertTrue(after.buttonActions.isEmpty, "the pinch still held after the cancel is not a new pinch")
        XCTAssertEqual((d.pinch(count: 3) + d.open(count: 2)).buttonActions, [.leftClick], "a new pinch works")
    }

    func testCancelDuringAPendingClickNeverClicks() {
        var d = HandDriver()
        _ = d.pinch(count: 3)
        XCTAssertEqual(d.engine.cancel(), [], "no mouseDown was sent, so no mouseUp either")
        XCTAssertTrue((d.pinch(count: 2) + d.open(count: 3)).buttonActions.isEmpty)
    }

    func testResetDuringDragReleasesTheButton() {
        var d = HandDriver()
        _ = dragging(&d)
        XCTAssertEqual(d.engine.reset(), [.endDrag])
        XCTAssertFalse(d.engine.pinchIntent.isButtonDown)
    }

    func testOutputOffDuringDragReleasesOnceThenOnlyObserves() {
        var d = HandDriver()
        _ = dragging(&d)
        d.outputs = [.scroll]
        let off = d.pinch(count: 3, move: right)
        XCTAssertEqual(off[0].actions, [.endDrag])
        XCTAssertTrue(off.allSatisfy { $0.appliedCursorPolicy == .follow })
        d.outputs = .all
        let back = d.pinch(count: 3, move: right) + d.open(count: 2)
        XCTAssertTrue(back.buttonActions.isEmpty, "the silenced pinch stays shadow until released")
    }

    func testOutputOffDuringAPendingClickNeverClicks() {
        var d = HandDriver()
        _ = d.pinch(count: 3)
        d.outputs = []
        XCTAssertTrue(d.open(count: 3).allSatisfy { $0.actions.isEmpty })
    }

    func testShadowPinchIsRecognizedButNeverTouchesTheCursorOrButton() {
        var d = HandDriver()
        d.outputs = [.scroll]
        let frames = d.pinch(count: 2) + d.pinch(count: 6, move: right) + d.open(count: 2) + d.pinch(count: 2) + d.open(count: 2)
        XCTAssertTrue(frames.contains { $0.intent == .pinch && $0.cursorPolicy == .drag }, "advisory policy still reported")
        XCTAssertTrue(frames.allSatisfy { $0.actions.isEmpty && $0.appliedCursorPolicy == .follow && !$0.pinch.buttonDown })
    }

    // MARK: Conflicts

    func testActiveScrollBlocksClickAndDrag() {
        var d = HandDriver()
        d.center = Point2D(x: 0.5, y: 0.35)
        let scroll = d.run(TestPoses.twoFingers, .folded, move: Point2D(x: 0, y: 0.01), count: 6)
        XCTAssertEqual(scroll.last?.intent, .twoFingerScroll)
        let pinch = d.pinch(count: 8, move: Point2D(x: 0.01, y: 0))
        XCTAssertTrue(pinch.allSatisfy { $0.intent != .pinch }, "the pinch that ends a scroll is part of it")
        XCTAssertFalse(pinch.last?.pinch.armed ?? true)
        XCTAssertTrue((scroll + pinch + d.open(count: 3)).buttonActions.isEmpty)
        XCTAssertEqual((d.pinch(count: 3) + d.open(count: 2)).buttonActions, [.leftClick], "a new pinch after it clicks")
    }

    func testActiveDragBlocksScroll() {
        var d = HandDriver()
        d.center = Point2D(x: 0.5, y: 0.35)
        _ = dragging(&d, move: Point2D(x: 0, y: 0.01), count: 4)
        let vertical = d.pinch(count: 10, move: Point2D(x: 0, y: 0.01))
        XCTAssertTrue(vertical.allSatisfy { $0.intent == .pinch && $0.scrollState == .idle })
        XCTAssertTrue(InteractionScenario.scrolls(vertical).isEmpty)
    }

    func testPinchDuringInertiaStopsItWithoutClicking() {
        var d = HandDriver()
        d.center = Point2D(x: 0.5, y: 0.3)
        _ = d.run(TestPoses.twoFingers, .folded, move: Point2D(x: 0, y: 0.01), count: 8)
        _ = d.run(TestPoses.pointing, .folded, count: 4)
        XCTAssertEqual(d.engine.scroll.state, .momentum)
        let pinch = d.pinch(count: 6)
        XCTAssertEqual(d.engine.scroll.state, .idle, "touching again stops inertia")
        XCTAssertTrue((pinch + d.open(count: 3)).buttonActions.isEmpty, "…and that touch is not a click")
    }

    func testOtherPosesNeverClickOrDrag() {
        var d = HandDriver()
        let frames = d.run(TestPoses.twoFingers, .folded, move: Point2D(x: 0.01, y: 0), count: 10)
            + d.run(TestPoses.fourFingers, .extended, count: 10)
            + d.run(TestPoses.twoFingers, .touchingMiddle, count: 10)
            + d.run(TestPoses.pointing, .folded, move: Point2D(x: -0.01, y: 0.005), count: 10)
        XCTAssertTrue(frames.buttonActions.isEmpty)
        XCTAssertTrue(frames.allSatisfy { $0.intent != .pinch })
    }

    func testPointingWithTheThumbNearbyNeverClicks() {
        var d = HandDriver()
        // Thumb resting just outside the enter distance while pointing and moving.
        let frames = d.run(count: 30, thumbDistance: 0.3) + d.open(count: 3, move: Point2D(x: 0.005, y: 0))
        XCTAssertTrue(frames.buttonActions.isEmpty)
        XCTAssertTrue(frames.allSatisfy { $0.appliedCursorPolicy == .follow })
    }

    func testSameInputGivesSameActions() {
        func run() -> [InteractionFrame] {
            var d = HandDriver()
            return d.pinch(count: 3) + d.open(count: 2) + d.pinch(count: 2) + d.pinch(count: 6, move: right) + d.open(count: 2)
        }
        XCTAssertEqual(run(), run())
        XCTAssertEqual(run().buttonActions, [.leftClick, .beginDrag, .endDrag])
    }
}
