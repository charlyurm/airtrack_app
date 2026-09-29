import XCTest
@testable import AirTrackCore

/// PHASE 2.1: CursorController driven by PointerTracker decisions (hold, loss, degraded
/// modes, reacquisition) and the adaptive smoother inside the controller.
final class CursorPointerIntegrationTests: XCTestCase {
    private let display = Rect2D(x: 0, y: 0, width: 1440, height: 900)
    private let dt = 1.0 / 30

    private func settings(smoothing: Double = 0, speedResponse: Double = 0, deadZone: Double = 0, blend: TimeInterval = 0) -> AirTrackSettings {
        var s = AirTrackSettings()
        s.cursorSmoothing = smoothing
        s.cursorSpeedResponse = speedResponse
        s.cursorDeadZone = deadZone
        s.cursorReacquisitionBlend = blend
        return s
    }

    private func pointer(_ mode: PointerTrackingMode, _ tip: Point2D?, _ time: TimeInterval, starts: Bool = false) -> PointerObservation {
        PointerObservation(mode: mode, indexTip: tip, indexConfidence: tip == nil ? nil : 0.9, timestamp: time, startsSession: starts)
    }

    // MARK: Controller with pointer decisions

    func testPartialAndIndexPointersMoveTheCursorLikeAFullHand() {
        for mode in [PointerTrackingMode.full, .partial, .indexContinuity] {
            var c = CursorController(settings: settings())
            let update = c.update(pointer: pointer(mode, Point2D(x: 0.5, y: 0.5), 0, starts: true), display: display, isActive: true)
            XCTAssertPointEqual(update?.screen, Point2D(x: 720, y: 450), accuracy: 1e-6)
        }
    }

    func testHoldingKeepsTheCursorStillAndTheSessionAlive() {
        var c = CursorController(settings: settings(blend: 0.2))
        _ = c.update(pointer: pointer(.full, Point2D(x: 0.5, y: 0.5), 0, starts: true), display: display, isActive: true)
        _ = c.update(pointer: pointer(.full, Point2D(x: 0.5, y: 0.5), 0.3), display: display, isActive: true) // blend finished
        XCTAssertNil(c.update(pointer: pointer(.holding, nil, 0.333), display: display, isActive: true), "no event while holding")
        XCTAssertTrue(c.isTracking, "a hold is not a loss")
        XCTAssertFalse(c.needsReferencePosition)
        // The hand continues: the cursor follows the NEW position, without a reacquisition glide.
        let next = c.update(pointer: pointer(.full, Point2D(x: 0.4, y: 0.5), 0.366), display: display, isActive: true, currentCursor: Point2D(x: 0, y: 0))
        XCTAssertEqual(next?.target.x ?? -1, CursorMapper().map(Point2D(x: 0.4, y: 0.5))!.x, accuracy: 1e-9)
        XCTAssertPointEqual(next?.normalized, next!.target, accuracy: 1e-9)
    }

    func testLostDropsTheSession() {
        var c = CursorController(settings: settings(smoothing: 0.8))
        _ = c.update(pointer: pointer(.full, Point2D(x: 0.3, y: 0.3), 0, starts: true), display: display, isActive: true)
        XCTAssertNil(c.update(pointer: pointer(.lost, nil, 0.1), display: display, isActive: true))
        XCTAssertTrue(c.needsReferencePosition)
        let back = c.update(pointer: pointer(.full, Point2D(x: 0.7, y: 0.7), 0.2, starts: true), display: display, isActive: true)!
        XCTAssertPointEqual(back.normalized, back.target, accuracy: 1e-12, "no stale smoothing after a loss")
    }

    func testANewSessionGlidesFromTheCurrentCursor() {
        var c = CursorController(settings: settings(blend: 0.2))
        let cursorNow = Point2D(x: 360, y: 225)
        let first = c.update(pointer: pointer(.full, Point2D(x: 0.5, y: 0.5), 1.0, starts: true), display: display, isActive: true, currentCursor: cursorNow)
        XCTAssertPointEqual(first?.screen, cursorNow, accuracy: 1e-6)
        let done = c.update(pointer: pointer(.full, Point2D(x: 0.5, y: 0.5), 1.25), display: display, isActive: true)
        XCTAssertPointEqual(done?.screen, Point2D(x: 720, y: 450), accuracy: 1e-6)
    }

    func testStartsSessionForcesAFreshStart() {
        var c = CursorController(settings: settings(smoothing: 0.9))
        _ = c.update(pointer: pointer(.full, Point2D(x: 0.2, y: 0.2), 0, starts: true), display: display, isActive: true)
        let fresh = c.update(pointer: pointer(.full, Point2D(x: 0.8, y: 0.8), dt, starts: true), display: display, isActive: true)!
        XCTAssertPointEqual(fresh.normalized, fresh.target, accuracy: 1e-12)
    }

    func testInactiveOrMissingTipMovesNothing() {
        var c = CursorController(settings: settings())
        XCTAssertNil(c.update(pointer: pointer(.full, Point2D(x: 0.5, y: 0.5), 0), display: display, isActive: false))
        XCTAssertNil(c.update(pointer: pointer(.full, nil, 0), display: display, isActive: true))
        XCTAssertNil(c.update(pointer: pointer(.full, Point2D(x: .nan, y: 0.5), 0), display: display, isActive: true))
        XCTAssertNil(c.update(pointer: pointer(.full, Point2D(x: 0.5, y: 0.5), 0), display: Rect2D(x: 0, y: 0, width: 0, height: 0), isActive: true))
    }

    func testObservationWithoutPointerModeCarriesNoTip() {
        let hold = PointerObservation(mode: .holding, indexTip: Point2D(x: 0.5, y: 0.5), timestamp: 0)
        XCTAssertNil(hold.indexTip, "holding/lost can never carry a position")
        XCTAssertNil(PointerObservation(mode: .lost, indexTip: Point2D(x: 0.5, y: 0.5), timestamp: 0).indexTip)
    }

    // MARK: Adaptive smoothing inside the controller

    func testFastMovementFollowsCloserThanFixedSmoothing() {
        var adaptive = CursorController(settings: settings(smoothing: 0.6, speedResponse: 1))
        var fixed = CursorController(settings: settings(smoothing: 0.6, speedResponse: 0))
        var a: CursorUpdate?
        var f: CursorUpdate?
        for i in 0..<10 {
            // 0.6 of the image in 1/3 s: a fast horizontal sweep.
            let tip = Point2D(x: 0.2 + 0.06 * Double(i), y: 0.5)
            let p = pointer(.full, tip, Double(i) * dt, starts: i == 0)
            a = adaptive.update(pointer: p, display: display, isActive: true)
            f = fixed.update(pointer: p, display: display, isActive: true)
        }
        let adaptiveLag = abs(a!.target.x - a!.normalized.x)
        let fixedLag = abs(f!.target.x - f!.normalized.x)
        XCTAssertLessThan(adaptiveLag, fixedLag / 2)
        XCTAssertGreaterThan(a!.speed, 1)
        XCTAssertLessThan(a!.smoothing, 0.3)
    }

    func testStillFingerReportsFullRestSmoothing() {
        var c = CursorController(settings: settings(smoothing: 0.6, speedResponse: 1, deadZone: 0.003))
        var last: CursorUpdate?
        for i in 0..<10 {
            last = c.update(pointer: pointer(.full, Point2D(x: 0.5, y: 0.5), Double(i) * dt, starts: i == 0), display: display, isActive: true)
        }
        XCTAssertEqual(last?.speed, 0)
        XCTAssertEqual(last?.smoothing ?? 0, 0.6, accuracy: 1e-9)
    }

    // MARK: Tracker + controller (bottom edge, dropouts)

    /// N2/N3: the hand slides toward the bottom of the image until the wrist and the knuckles
    /// leave it. The cursor must keep following the index down to the bottom screen edge.
    func testIndexReachesTheBottomScreenEdgeWhileThePalmLeavesTheImage() {
        var tracker = PointerTracker()
        var c = CursorController(settings: settings())
        let tipOffset = TestHands.openHandOffsets[.indexTip]!
        var tip = Point2D(x: 0.5, y: 0.6)
        var lastScreenY = -1.0
        for i in 0..<40 {
            if i >= 2 { tip = Point2D(x: 0.5, y: min(tip.y + 0.01, 0.95)) }
            let hand = TestHands.openHand(at: Double(i) * dt, center: tip - tipOffset)
            let frame = tracker.update(candidates: [hand], timestamp: Double(i) * dt)
            let update = c.update(pointer: frame.pointer, display: display, isActive: true)
            if i >= 1 {
                XCTAssertNotNil(update, "frame \(i), tip y \(tip.y), mode \(frame.pointer.mode)")
                if let update {
                    XCTAssertGreaterThanOrEqual(update.screen.y, lastScreenY - 1e-9, "cursor keeps moving down")
                    lastScreenY = update.screen.y
                }
            }
        }
        XCTAssertEqual(lastScreenY, 899, accuracy: 1e-6, "the bottom screen edge is reachable")
    }

    func testOneMissedFrameDoesNotRestartTheCursor() {
        var tracker = PointerTracker()
        var c = CursorController(settings: settings(blend: 0.2))
        let tipOffset = TestHands.openHandOffsets[.indexTip]!
        var outputs: [CursorUpdate?] = []
        for i in 0..<8 {
            let tip = Point2D(x: 0.4 + 0.01 * Double(i), y: 0.5)
            let candidates = i == 4 ? [] : [TestHands.openHand(at: Double(i) * dt, center: tip - tipOffset)]
            let frame = tracker.update(candidates: candidates, timestamp: Double(i) * dt)
            let reference = c.needsReferencePosition ? Point2D(x: 0, y: 0) : nil
            outputs.append(c.update(pointer: frame.pointer, display: display, isActive: true, currentCursor: reference))
        }
        XCTAssertNil(outputs[4], "the missed frame posts nothing")
        XCTAssertNotNil(outputs[5], "the very next frame moves again (no 2-frame gate, no new glide)")
        XCTAssertEqual(tracker.mode, .full)
        // Still gliding from the original acquisition, never restarted at the missed frame.
        XCTAssertTrue(c.isTracking)
    }
}
