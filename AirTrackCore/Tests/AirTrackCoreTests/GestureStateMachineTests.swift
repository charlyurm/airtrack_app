import XCTest
@testable import AirTrackCore

final class GestureStateMachineTests: XCTestCase {
    private let config = GestureConfiguration(
        doubleClickInterval: 0.4,
        doubleClickMaxDistance: 0.02,
        dragHoldDuration: 0.3,
        dragMovementThreshold: 0.03,
        anchorLookback: 0,
        trackingLossGracePeriod: 0.15
    )

    private func p(_ x: Double, _ y: Double = 0.5) -> Point2D { Point2D(x: x, y: y) }

    @discardableResult
    private func frame(_ sm: inout GestureStateMachine, _ t: Double, _ x: Double, pinched: Bool) -> GestureOutput {
        sm.update(.frame(timestamp: t, cursor: p(x), isPinched: pinched))
    }

    /// State machine that has seen an open hand at x = 0.5 (armed, pointing).
    private func armedMachine(_ configuration: GestureConfiguration? = nil) -> GestureStateMachine {
        var sm = GestureStateMachine(configuration: configuration ?? config)
        frame(&sm, 0, 0.5, pinched: false)
        return sm
    }

    /// Armed machine that is dragging at x = 0.56 since t = 0.066.
    private func draggingMachine() -> GestureStateMachine {
        var sm = armedMachine()
        frame(&sm, 0.033, 0.5, pinched: true)
        let out = frame(&sm, 0.066, 0.56, pinched: true)
        XCTAssertEqual(out.events, [.dragStarted])
        return sm
    }

    private func clickCount(in actions: [InteractionAction]) -> (downs: Int, ups: Int) {
        var downs = 0, ups = 0
        for action in actions {
            if case .mouseDown = action { downs += 1 }
            if case .mouseUp = action { ups += 1 }
        }
        return (downs, ups)
    }

    // MARK: Pointing

    func testPointingMovesCursorOnlyWhenItChanges() {
        var sm = GestureStateMachine(configuration: config)
        XCTAssertEqual(frame(&sm, 0, 0.5, pinched: false).actions, [.moveCursor(to: p(0.5))])
        XCTAssertEqual(sm.phase, .pointing)
        XCTAssertEqual(frame(&sm, 0.033, 0.5, pinched: false).actions, [])
        XCTAssertEqual(frame(&sm, 0.066, 0.6, pinched: false).actions, [.moveCursor(to: p(0.6))])
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
        XCTAssertEqual(clickCount(in: start.actions).downs, 0)
        if case .clickCandidate = sm.phase {} else { XCTFail("expected clickCandidate, got \(sm.phase)") }
    }

    func testCursorIsFrozenDuringClickCandidateAndClickLandsOnAnchor() {
        var sm = armedMachine()
        frame(&sm, 0.033, 0.5, pinched: true)
        // Fingertip drifts while the fingers close (below the drag threshold).
        XCTAssertEqual(frame(&sm, 0.066, 0.51, pinched: true).actions, [])
        XCTAssertEqual(frame(&sm, 0.1, 0.52, pinched: true).actions, [])
        let release = frame(&sm, 0.133, 0.525, pinched: false)
        XCTAssertEqual(release.actions, [.mouseDown(at: p(0.5), clickCount: 1), .mouseUp(at: p(0.5), clickCount: 1)])
        // Pointing resumes on the next frame.
        XCTAssertEqual(frame(&sm, 0.166, 0.525, pinched: false).actions, [.moveCursor(to: p(0.525))])
    }

    func testClickAnchorUsesPositionFromBeforeTheFingersClosed() {
        var sm = GestureStateMachine(configuration: GestureConfiguration(anchorLookback: 0.07))
        frame(&sm, 0, 0.5, pinched: false)
        frame(&sm, 0.033, 0.5, pinched: false)
        frame(&sm, 0.066, 0.505, pinched: false)
        // Pinch confirmed at t = 0.1 after the tip already drifted to 0.51.
        let start = frame(&sm, 0.1, 0.51, pinched: true)
        XCTAssertEqual(start.actions, [.moveCursor(to: p(0.5))])
        let release = frame(&sm, 0.133, 0.512, pinched: false)
        XCTAssertEqual(release.actions, [.mouseDown(at: p(0.5), clickCount: 1), .mouseUp(at: p(0.5), clickCount: 1)])
    }

    // MARK: Drag

    func testHoldingThePinchEntersDragAndTheCursorFollows() {
        var sm = armedMachine()
        frame(&sm, 0.033, 0.5, pinched: true)
        XCTAssertEqual(frame(&sm, 0.2, 0.5, pinched: true).actions, [])

        let dragStart = frame(&sm, 0.34, 0.505, pinched: true)
        XCTAssertEqual(dragStart.actions, [.mouseDown(at: p(0.5), clickCount: 1), .mouseDrag(to: p(0.505))])
        XCTAssertEqual(dragStart.events, [.dragStarted])

        XCTAssertEqual(frame(&sm, 0.37, 0.6, pinched: true).actions, [.mouseDrag(to: p(0.6))])
        XCTAssertEqual(frame(&sm, 0.4, 0.7, pinched: true).actions, [.mouseDrag(to: p(0.7))])

        let release = frame(&sm, 0.43, 0.72, pinched: false)
        XCTAssertEqual(release.actions, [.mouseUp(at: p(0.7), clickCount: 1)])
        XCTAssertEqual(release.events, [.dragEnded])
        XCTAssertEqual(sm.phase, .pointing)
    }

    func testLargeMovementStartsDragImmediately() {
        var sm = armedMachine()
        frame(&sm, 0.033, 0.5, pinched: true)
        let out = frame(&sm, 0.066, 0.56, pinched: true)
        XCTAssertEqual(out.actions, [.mouseDown(at: p(0.5), clickCount: 1), .mouseDrag(to: p(0.56))])
        XCTAssertEqual(sm.phase, .dragging(position: p(0.56)))
    }

    func testDragIsNotAClick() {
        var sm = draggingMachine()
        let out = frame(&sm, 0.1, 0.56, pinched: false)
        XCTAssertFalse(out.events.contains(.clicked(clickCount: 1)))
        // A quick pinch right after a drag is a fresh single click, not a double click.
        frame(&sm, 0.133, 0.56, pinched: true)
        let click = frame(&sm, 0.166, 0.56, pinched: false)
        XCTAssertEqual(click.events, [.clicked(clickCount: 1)])
    }

    // MARK: Double click

    private func clickOnce(_ sm: inout GestureStateMachine, pinchAt: Double, releaseAt: Double, x: Double = 0.5) -> GestureOutput {
        frame(&sm, pinchAt, x, pinched: true)
        return frame(&sm, releaseAt, x, pinched: false)
    }

    func testTwoQuickPinchesProduceADoubleClickAtTheFirstPosition() {
        var sm = armedMachine()
        XCTAssertEqual(clickOnce(&sm, pinchAt: 0.033, releaseAt: 0.1).events, [.clicked(clickCount: 1)])
        frame(&sm, 0.133, 0.505, pinched: false)

        let secondStart = frame(&sm, 0.2, 0.51, pinched: true)
        XCTAssertEqual(secondStart.events, [.pinchStarted(clickCount: 2)])
        let release = frame(&sm, 0.25, 0.51, pinched: false)
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
        frame(&sm, 0.133, 0.6, pinched: false)
        let out = clickOnce(&sm, pinchAt: 0.2, releaseAt: 0.25, x: 0.6)
        XCTAssertEqual(out.actions, [.mouseDown(at: p(0.6), clickCount: 1), .mouseUp(at: p(0.6), clickCount: 1)])
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

    // MARK: Tracking loss

    func testTrackingLossDuringDragReleasesTheMouseAfterTheGracePeriod() {
        var sm = draggingMachine()
        XCTAssertEqual(sm.update(.trackingLost(timestamp: 0.1)), .empty)
        XCTAssertEqual(sm.update(.trackingLost(timestamp: 0.2)), .empty)
        let out = sm.update(.trackingLost(timestamp: 0.26))
        XCTAssertEqual(out.actions, [.mouseUp(at: p(0.56), clickCount: 1)])
        XCTAssertEqual(out.events, [.cancelled(.trackingLost)])
        XCTAssertEqual(sm.phase, .idle)
    }

    func testShortTrackingDropoutDoesNotInterruptADrag() {
        var sm = draggingMachine()
        XCTAssertEqual(sm.update(.trackingLost(timestamp: 0.1)), .empty)
        XCTAssertEqual(frame(&sm, 0.133, 0.6, pinched: true).actions, [.mouseDrag(to: p(0.6))])
        // The grace timer restarts after tracking returns.
        XCTAssertEqual(sm.update(.trackingLost(timestamp: 0.2)), .empty)
        XCTAssertEqual(sm.update(.trackingLost(timestamp: 0.3)), .empty)
        XCTAssertEqual(sm.phase, .dragging(position: p(0.6)))
    }

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

    // MARK: Pause

    func testPauseWhileDraggingReleasesTheMouseImmediately() {
        var sm = draggingMachine()
        let out = sm.update(.paused(timestamp: 0.1))
        XCTAssertEqual(out.actions, [.mouseUp(at: p(0.56), clickCount: 1)])
        XCTAssertEqual(out.events, [.cancelled(.paused)])
        XCTAssertEqual(sm.update(.paused(timestamp: 0.133)), .empty)
    }

    func testPauseDuringClickCandidateSendsNothing() {
        var sm = armedMachine()
        frame(&sm, 0.033, 0.5, pinched: true)
        let out = sm.update(.paused(timestamp: 0.066))
        XCTAssertEqual(out.actions, [])
        XCTAssertEqual(out.events, [.cancelled(.paused)])
    }
}
