import XCTest
@testable import AirTrackCore

/// Positions use dyadic values (0.5, 0.625, 1/128 …) so sums and differences are exact
/// in binary floating point and position assertions can be exact.
final class GestureStateMachineTests: XCTestCase {
    private let config = GestureConfiguration(
        doubleClickInterval: 0.4,
        doubleClickMaxDistance: 0.02,
        dragHoldDuration: 0.3,
        dragMovementThreshold: 0.03,
        anchorLookback: 0,
        trackingLossGracePeriod: 0.15,
        dragOffsetDecayDuration: 0.2
    )

    private func p(_ x: Double, _ y: Double = 0.5) -> Point2D { Point2D(x: x, y: y) }

    @discardableResult
    private func frame(_ sm: inout GestureStateMachine, _ t: Double, _ x: Double, _ y: Double = 0.5, pinched: Bool) -> GestureOutput {
        sm.update(.frame(timestamp: t, finger: p(x, y), isPinched: pinched))
    }

    /// State machine that has seen an open hand at x = 0.5 (armed, pointing).
    private func armedMachine(_ configuration: GestureConfiguration? = nil) -> GestureStateMachine {
        var sm = GestureStateMachine(configuration: configuration ?? config)
        frame(&sm, 0, 0.5, pinched: false)
        return sm
    }

    /// Armed machine that pinched at x = 0.5, then moved the finger to 0.625, which starts a
    /// drag at the anchor 0.5 with offset −0.125.
    private func draggingMachine() -> GestureStateMachine {
        var sm = armedMachine()
        frame(&sm, 0.033, 0.5, pinched: true)
        let out = frame(&sm, 0.066, 0.625, pinched: true)
        XCTAssertEqual(out.events, [.dragStarted])
        XCTAssertEqual(sm.phase, .dragging(position: p(0.5), offset: Point2D(x: -0.125, y: 0)))
        return sm
    }

    private func count(_ actions: [InteractionAction]) -> (downs: Int, drags: Int, ups: Int) {
        var downs = 0, drags = 0, ups = 0
        for action in actions {
            switch action {
            case .mouseDown: downs += 1
            case .mouseDrag: drags += 1
            case .mouseUp: ups += 1
            case .moveCursor, .scroll, .leftClick, .beginDrag, .endDrag: break
            }
        }
        return (downs, drags, ups)
    }

    private func position(of action: InteractionAction) -> Point2D {
        switch action {
        case let .moveCursor(to), let .mouseDrag(to): return to
        case let .mouseDown(at, _), let .mouseUp(at, _): return at
        case .scroll, .leftClick, .beginDrag, .endDrag:
            XCTFail("the Phase 0 state machine never produces Phase 3 actions")
            return .zero
        }
    }

    // MARK: Pointing

    func testPointingMovesCursorOnlyWhenItChanges() {
        var sm = GestureStateMachine(configuration: config)
        XCTAssertEqual(frame(&sm, 0, 0.5, pinched: false).actions, [.moveCursor(to: p(0.5))])
        XCTAssertEqual(sm.phase, .pointing)
        XCTAssertEqual(frame(&sm, 0.033, 0.5, pinched: false).actions, [])
        XCTAssertEqual(frame(&sm, 0.066, 0.625, pinched: false).actions, [.moveCursor(to: p(0.625))])
    }

    // MARK: Click

    func testSinglePinchProducesExactlyOneClick() {
        var sm = armedMachine()
        var actions: [InteractionAction] = []
        var events: [GestureEvent] = []
        let inputs: [(Double, Bool)] = [(0.033, true), (0.066, true), (0.1, true), (0.133, false), (0.166, false), (0.2, false), (0.5, false)]
        for (t, pinched) in inputs {
            let out = frame(&sm, t, 0.5, pinched: pinched)
            actions += out.actions
            events += out.events
        }
        XCTAssertEqual(actions, [.mouseDown(at: p(0.5), clickCount: 1), .mouseUp(at: p(0.5), clickCount: 1)])
        XCTAssertEqual(events, [.pinchStarted(clickCount: 1), .clicked(clickCount: 1)])
    }

    func testNothingReachesTheOSUntilThePinchIsResolved() {
        var sm = armedMachine()
        let start = frame(&sm, 0.033, 0.5, pinched: true)
        XCTAssertEqual(start.events, [.pinchStarted(clickCount: 1)])
        XCTAssertEqual(count(start.actions).downs, 0)
        if case .clickCandidate = sm.phase {} else { XCTFail("expected clickCandidate, got \(sm.phase)") }
    }

    func testCursorIsFrozenDuringClickCandidateAndClickLandsOnAnchor() {
        var sm = armedMachine()
        frame(&sm, 0.033, 0.5, pinched: true)
        // Fingertip drifts while the fingers close (below the drag threshold).
        XCTAssertEqual(frame(&sm, 0.066, 0.5078125, pinched: true).actions, [])
        XCTAssertEqual(frame(&sm, 0.1, 0.515625, pinched: true).actions, [])
        let release = frame(&sm, 0.133, 0.5234375, pinched: false)
        XCTAssertEqual(release.actions, [.mouseDown(at: p(0.5), clickCount: 1), .mouseUp(at: p(0.5), clickCount: 1)])
        // Pointing resumes on the next frame.
        XCTAssertEqual(frame(&sm, 0.166, 0.5234375, pinched: false).actions, [.moveCursor(to: p(0.5234375))])
    }

    func testClickAnchorUsesPositionFromBeforeTheFingersClosed() {
        var sm = GestureStateMachine(configuration: GestureConfiguration(anchorLookback: 0.07))
        frame(&sm, 0, 0.5, pinched: false)
        frame(&sm, 0.033, 0.5, pinched: false)
        frame(&sm, 0.066, 0.50390625, pinched: false)
        // Pinch confirmed at t = 0.1 after the tip already drifted to 0.5078125.
        let start = frame(&sm, 0.1, 0.5078125, pinched: true)
        XCTAssertEqual(start.actions, [.moveCursor(to: p(0.5))])
        let release = frame(&sm, 0.133, 0.5078125, pinched: false)
        XCTAssertEqual(release.actions, [.mouseDown(at: p(0.5), clickCount: 1), .mouseUp(at: p(0.5), clickCount: 1)])
    }

    // MARK: Drag — continuity (no anchor jump)

    func testDragStartsWithoutAJump() {
        var sm = armedMachine()
        frame(&sm, 0.033, 0.5, pinched: true)
        // The pinch dragged the tip by 1/128 while the cursor was frozen on the anchor.
        XCTAssertEqual(frame(&sm, 0.2, 0.5078125, pinched: true).actions, [])

        let entry = frame(&sm, 0.34, 0.5078125, pinched: true)
        XCTAssertEqual(entry.actions, [.mouseDown(at: p(0.5), clickCount: 1)], "no drag event, cursor stays on the anchor")
        XCTAssertEqual(entry.events, [.dragStarted])
        XCTAssertEqual(sm.phase, .dragging(position: p(0.5), offset: Point2D(x: -0.0078125, y: 0)))
    }

    func testMovementTriggeredDragStartsWithoutAJump() {
        var sm = armedMachine()
        frame(&sm, 0.033, 0.5, pinched: true)
        let entry = frame(&sm, 0.066, 0.625, pinched: true)
        XCTAssertEqual(entry.actions, [.mouseDown(at: p(0.5), clickCount: 1)])
        XCTAssertEqual(sm.phase, .dragging(position: p(0.5), offset: Point2D(x: -0.125, y: 0)))
    }

    func testOffsetIsPreservedThroughoutTheDrag() {
        var sm = draggingMachine()
        let fingers: [(Double, Double)] = [(0.75, 0.5), (0.875, 0.625), (0.3125, 0.25), (0.6875, 0.75)]
        for (i, f) in fingers.enumerated() {
            frame(&sm, 0.1 + Double(i) * 0.033, f.0, f.1, pinched: true)
            guard case let .dragging(_, offset) = sm.phase else {
                return XCTFail("left dragging at step \(i): \(sm.phase)")
            }
            XCTAssertEqual(offset, Point2D(x: -0.125, y: 0))
        }
    }

    func testFingerMovementProducesEquivalentCursorMovement() {
        var sm = draggingMachine()
        let fingers: [(Double, Double)] = [(0.75, 0.5), (0.875, 0.625), (0.8125, 0.4375)]
        var drags: [Point2D] = []
        for (i, f) in fingers.enumerated() {
            let out = frame(&sm, 0.1 + Double(i) * 0.033, f.0, f.1, pinched: true)
            drags += out.actions.map(position(of:))
        }
        XCTAssertEqual(drags, [p(0.625, 0.5), p(0.75, 0.625), p(0.6875, 0.4375)])
        // Every finger delta is reproduced exactly by the cursor.
        for i in 1..<fingers.count {
            let fingerDelta = p(fingers[i].0, fingers[i].1) - p(fingers[i - 1].0, fingers[i - 1].1)
            XCTAssertEqual(drags[i] - drags[i - 1], fingerDelta)
        }
    }

    func testCursorNeverChangesAbruptlyWhenEnteringDrag() {
        var sm = armedMachine()
        var trace: [(t: Double, finger: Double, actions: [InteractionAction])] = []
        let inputs: [(Double, Double)] = [
            (0.033, 0.5),
            (0.1, 0.5234375),  // pinch drift: 3/128, below the 0.03 movement threshold
            (0.2, 0.5234375),
            (0.34, 0.5234375), // hold time reached → DRAG
            (0.37, 0.5859375), // finger +1/16
            (0.4, 0.6484375),  // finger +1/16
        ]
        for (t, x) in inputs {
            trace.append((t, x, frame(&sm, t, x, pinched: true).actions))
        }

        // Entry frame: the finger did not move, so the cursor must not move either.
        XCTAssertEqual(trace[3].actions, [.mouseDown(at: p(0.5), clickCount: 1)])
        // Every cursor position ever emitted before the finger moves is the anchor.
        for step in trace[0...3] {
            for action in step.actions { XCTAssertEqual(position(of: action), p(0.5)) }
        }
        // After entry the cursor moves exactly as much as the finger.
        XCTAssertEqual(trace[4].actions, [.mouseDrag(to: p(0.5625))])
        XCTAssertEqual(trace[5].actions, [.mouseDrag(to: p(0.625))])
    }

    func testDragPositionStaysOnScreen() {
        var sm = draggingMachine()
        XCTAssertEqual(frame(&sm, 0.1, 0.0625, pinched: true).actions, [.mouseDrag(to: p(0))])
    }

    func testShortPinchDoesNotEnterDrag() {
        var sm = armedMachine()
        var all: [InteractionAction] = []
        var events: [GestureEvent] = []
        for (t, x, pinched) in [(0.033, 0.5, true), (0.1, 0.5078125, true), (0.2, 0.515625, true), (0.25, 0.515625, false)] {
            let out = frame(&sm, t, x, pinched: pinched)
            all += out.actions
            events += out.events
        }
        XCTAssertEqual(count(all).drags, 0)
        XCTAssertFalse(events.contains(.dragStarted))
        XCTAssertEqual(events.last, .clicked(clickCount: 1))
    }

    // MARK: Drag — termination

    func testReleaseEndsDragWithoutSnappingBack() {
        var sm = draggingMachine()
        let release = frame(&sm, 0.1, 0.625, pinched: false)
        XCTAssertEqual(release.actions, [.mouseUp(at: p(0.5), clickCount: 1)])
        XCTAssertEqual(release.events, [.dragEnded])
        XCTAssertEqual(sm.phase, .pointing)

        // Halfway through the 0.2 s decay: half of the −0.125 offset remains.
        let halfway = frame(&sm, 0.2, 0.625, pinched: false)
        XCTAssertEqual(halfway.actions.count, 1)
        XCTAssertPointEqual(halfway.actions.first.map(position(of:)), p(0.5625))

        // Decay finished: the cursor is back on the finger.
        let done = frame(&sm, 0.5, 0.625, pinched: false)
        XCTAssertEqual(done.actions, [.moveCursor(to: p(0.625))])
    }

    func testDragIsNotAClick() {
        var sm = draggingMachine()
        let out = frame(&sm, 0.1, 0.625, pinched: false)
        XCTAssertFalse(out.events.contains(.clicked(clickCount: 1)))
        // A quick pinch right after a drag is a fresh single click, not a double click.
        frame(&sm, 0.133, 0.625, pinched: true)
        let click = frame(&sm, 0.166, 0.625, pinched: false)
        XCTAssertEqual(click.events, [.clicked(clickCount: 1)])
    }

    func testTrackingLossEndsDragAfterTheGracePeriod() {
        var sm = draggingMachine()
        XCTAssertEqual(frame(&sm, 0.1, 0.75, pinched: true).actions, [.mouseDrag(to: p(0.625))])
        XCTAssertEqual(sm.update(.trackingLost(timestamp: 0.133)), .empty)
        XCTAssertEqual(sm.update(.trackingLost(timestamp: 0.2)), .empty)
        let out = sm.update(.trackingLost(timestamp: 0.3))
        XCTAssertEqual(out.actions, [.mouseUp(at: p(0.625), clickCount: 1)])
        XCTAssertEqual(out.events, [.cancelled(.trackingLost)])
        XCTAssertEqual(sm.phase, .idle)
    }

    func testShortTrackingDropoutDoesNotInterruptADrag() {
        var sm = draggingMachine()
        XCTAssertEqual(sm.update(.trackingLost(timestamp: 0.1)), .empty)
        XCTAssertEqual(frame(&sm, 0.133, 0.75, pinched: true).actions, [.mouseDrag(to: p(0.625))])
        // The grace timer restarts after tracking returns.
        XCTAssertEqual(sm.update(.trackingLost(timestamp: 0.2)), .empty)
        XCTAssertEqual(sm.update(.trackingLost(timestamp: 0.3)), .empty)
        XCTAssertEqual(sm.phase, .dragging(position: p(0.625), offset: Point2D(x: -0.125, y: 0)))
    }

    func testPauseEndsDragImmediately() {
        var sm = draggingMachine()
        let out = sm.update(.paused(timestamp: 0.1))
        XCTAssertEqual(out.actions, [.mouseUp(at: p(0.5), clickCount: 1)])
        XCTAssertEqual(out.events, [.cancelled(.paused)])
        XCTAssertEqual(sm.update(.paused(timestamp: 0.133)), .empty)
        // After resuming, no drag offset survives: the cursor goes straight to the finger.
        XCTAssertEqual(frame(&sm, 0.2, 0.625, pinched: false).actions, [.moveCursor(to: p(0.625))])
    }

    // MARK: Double click

    private func clickOnce(_ sm: inout GestureStateMachine, pinchAt: Double, releaseAt: Double, x: Double = 0.5) -> GestureOutput {
        frame(&sm, pinchAt, x, pinched: true)
        return frame(&sm, releaseAt, x, pinched: false)
    }

    func testTwoQuickPinchesProduceADoubleClickAtTheFirstPosition() {
        var sm = armedMachine()
        XCTAssertEqual(clickOnce(&sm, pinchAt: 0.033, releaseAt: 0.1).events, [.clicked(clickCount: 1)])
        frame(&sm, 0.133, 0.50390625, pinched: false)

        let secondStart = frame(&sm, 0.2, 0.5078125, pinched: true)
        XCTAssertEqual(secondStart.events, [.pinchStarted(clickCount: 2)])
        let release = frame(&sm, 0.25, 0.5078125, pinched: false)
        XCTAssertEqual(release.actions, [.mouseDown(at: p(0.5), clickCount: 2), .mouseUp(at: p(0.5), clickCount: 2)])
        XCTAssertEqual(release.events, [.clicked(clickCount: 2)])
    }

    func testSecondPinchAfterTheIntervalIsASingleClick() {
        var sm = armedMachine()
        _ = clickOnce(&sm, pinchAt: 0.033, releaseAt: 0.1)
        frame(&sm, 0.2, 0.5, pinched: false)
        XCTAssertEqual(clickOnce(&sm, pinchAt: 0.6, releaseAt: 0.65).events, [.clicked(clickCount: 1)])
    }

    func testSecondPinchFarAwayIsASingleClick() {
        var sm = armedMachine()
        _ = clickOnce(&sm, pinchAt: 0.033, releaseAt: 0.1)
        frame(&sm, 0.133, 0.625, pinched: false)
        let out = clickOnce(&sm, pinchAt: 0.2, releaseAt: 0.25, x: 0.625)
        XCTAssertEqual(out.actions, [.mouseDown(at: p(0.625), clickCount: 1), .mouseUp(at: p(0.625), clickCount: 1)])
    }

    func testHeldSecondPinchIsNeverADoubleClick() {
        var sm = armedMachine()
        var actions: [InteractionAction] = []
        actions += clickOnce(&sm, pinchAt: 0.033, releaseAt: 0.1).actions
        actions += frame(&sm, 0.2, 0.5, pinched: true).actions
        actions += frame(&sm, 0.35, 0.5, pinched: true).actions
        let dragStart = frame(&sm, 0.55, 0.5, pinched: true)
        actions += dragStart.actions
        XCTAssertEqual(dragStart.events, [.dragStarted])
        actions += frame(&sm, 0.6, 0.5, pinched: false).actions

        let doubleClickDowns = actions.filter {
            if case .mouseDown(_, 2) = $0 { return true }
            return false
        }
        XCTAssertTrue(doubleClickDowns.isEmpty, "a held pinch must never send clickCount 2")
    }

    func testThirdQuickPinchStartsANewSequence() {
        var sm = armedMachine()
        XCTAssertEqual(clickOnce(&sm, pinchAt: 0.033, releaseAt: 0.1).events, [.clicked(clickCount: 1)])
        XCTAssertEqual(clickOnce(&sm, pinchAt: 0.2, releaseAt: 0.25).events, [.clicked(clickCount: 2)])
        XCTAssertEqual(clickOnce(&sm, pinchAt: 0.3, releaseAt: 0.35).events, [.clicked(clickCount: 1)])
    }

    // MARK: Tracking loss / pause outside a drag

    func testTrackingLossDuringClickCandidateSendsNothing() {
        var sm = armedMachine()
        frame(&sm, 0.033, 0.5, pinched: true)
        XCTAssertEqual(sm.update(.trackingLost(timestamp: 0.066)), .empty)
        let out = sm.update(.trackingLost(timestamp: 0.25))
        XCTAssertEqual(out.actions, [])
        XCTAssertEqual(out.events, [.cancelled(.trackingLost)])
    }

    func testNoCursorEventsWhileTrackingIsLost() {
        var sm = armedMachine()
        for i in 1...30 {
            XCTAssertEqual(sm.update(.trackingLost(timestamp: Double(i) / 30)).actions, [])
        }
    }

    func testReacquiredPinchedHandDoesNotClickUntilItOpens() {
        var sm = draggingMachine()
        _ = sm.update(.trackingLost(timestamp: 0.1))
        _ = sm.update(.trackingLost(timestamp: 0.3))
        XCTAssertTrue(sm.requiresOpenHandBeforePinch)

        let back = frame(&sm, 0.4, 0.5, pinched: true)
        XCTAssertEqual(back.actions, [.moveCursor(to: p(0.5))])
        XCTAssertEqual(back.events, [])
        XCTAssertEqual(frame(&sm, 0.5, 0.5, pinched: false).events, [])
        XCTAssertEqual(frame(&sm, 0.6, 0.5, pinched: true).events, [.pinchStarted(clickCount: 1)])
    }

    func testHandAlreadyPinchedAtStartDoesNotClick() {
        var sm = GestureStateMachine(configuration: config)
        XCTAssertEqual(frame(&sm, 0, 0.5, pinched: true).events, [])
        XCTAssertEqual(frame(&sm, 0.5, 0.5, pinched: true).events, [])
        XCTAssertEqual(sm.phase, .pointing)
    }

    func testPauseDuringClickCandidateSendsNothing() {
        var sm = armedMachine()
        frame(&sm, 0.033, 0.5, pinched: true)
        let out = sm.update(.paused(timestamp: 0.066))
        XCTAssertEqual(out.actions, [])
        XCTAssertEqual(out.events, [.cancelled(.paused)])
    }
}
