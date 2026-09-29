import XCTest
@testable import AirTrackCore

/// PHASE 2: primary index tip → system cursor position.
///
/// Raw camera space (HandState): the camera faces the user, so when the user moves the hand
/// to THEIR left, the index tip moves to the RIGHT of the raw image (x grows). With the default
/// mirror, the cursor must then move LEFT on screen.
final class CursorControllerTests: XCTestCase {
    private let display = Rect2D(x: 0, y: 0, width: 1440, height: 900)

    /// Deterministic settings: no smoothing, dead zone or blend unless a test turns them on.
    private func settings(
        sensitivity: Double = 1,
        smoothing: Double = 0,
        deadZone: Double = 0,
        blend: TimeInterval = 0,
        area: Rect2D = CursorMapper.defaultActiveArea
    ) -> AirTrackSettings {
        var s = AirTrackSettings()
        s.cursorSensitivity = sensitivity
        s.cursorSmoothing = smoothing
        s.cursorDeadZone = deadZone
        s.cursorReacquisitionBlend = blend
        s.activeArea = area
        return s
    }

    /// Raw camera point whose MIRRORED position is (mx, my), i.e. what the user sees in the preview.
    private func raw(mirroredX mx: Double, y: Double) -> Point2D {
        Point2D(x: 1 - mx, y: y)
    }

    private func move(_ c: inout CursorController, to rawTip: Point2D, t: TimeInterval = 0, display: Rect2D? = nil, active: Bool = true, cursor: Point2D? = nil) -> CursorUpdate? {
        c.update(hands: [TestHands.pointing(at: rawTip, time: t)], timestamp: t, display: display ?? self.display, isActive: active, currentCursor: cursor)
    }

    // MARK: Mapping: center, edges, corners, outside, clamping

    func testCenterOfActiveAreaIsScreenCenter() {
        var c = CursorController(settings: settings())
        XCTAssertPointEqual(move(&c, to: Point2D(x: 0.5, y: 0.5))?.screen, Point2D(x: 720, y: 450))
    }

    func testActiveAreaEdgesReachScreenEdges() {
        var c = CursorController(settings: settings())
        XCTAssertEqual(move(&c, to: raw(mirroredX: 0.15, y: 0.5))?.screen.x ?? -1, 0, accuracy: 1e-6, "left")
        c.reset()
        XCTAssertEqual(move(&c, to: raw(mirroredX: 0.85, y: 0.5))?.screen.x ?? -1, 1439, accuracy: 1e-6, "right")
        c.reset()
        XCTAssertEqual(move(&c, to: raw(mirroredX: 0.5, y: 0.15))?.screen.y ?? -1, 0, accuracy: 1e-6, "top")
        c.reset()
        XCTAssertEqual(move(&c, to: raw(mirroredX: 0.5, y: 0.85))?.screen.y ?? -1, 899, accuracy: 1e-6, "bottom")
    }

    func testActiveAreaCornersReachScreenCorners() {
        let cases: [(Double, Double, Point2D)] = [
            (0.15, 0.15, Point2D(x: 0, y: 0)),
            (0.85, 0.15, Point2D(x: 1439, y: 0)),
            (0.15, 0.85, Point2D(x: 0, y: 899)),
            (0.85, 0.85, Point2D(x: 1439, y: 899)),
        ]
        for (mx, my, expected) in cases {
            var c = CursorController(settings: settings())
            XCTAssertPointEqual(move(&c, to: raw(mirroredX: mx, y: my))?.screen, expected, accuracy: 1e-6)
        }
    }

    func testFingerOutsideActiveAreaIsClampedToTheScreenEdge() {
        var c = CursorController(settings: settings())
        XCTAssertPointEqual(move(&c, to: raw(mirroredX: 0.02, y: 0.98))?.screen, Point2D(x: 0, y: 899), accuracy: 1e-6)
        c.reset()
        XCTAssertPointEqual(move(&c, to: raw(mirroredX: 0.99, y: 0.01))?.screen, Point2D(x: 1439, y: 0), accuracy: 1e-6)
    }

    // MARK: Directions

    func testHandMovingUpMovesCursorUp() {
        var c = CursorController(settings: settings())
        let low = move(&c, to: Point2D(x: 0.5, y: 0.7))!.screen.y
        let high = move(&c, to: Point2D(x: 0.5, y: 0.3))!.screen.y
        XCTAssertLessThan(high, low, "HandState y decreases when the hand goes up; screen y must decrease too")
    }

    func testHandMovingToTheUsersLeftMovesCursorLeft() {
        var c = CursorController(settings: settings())
        // User moves the hand to their left → raw image x grows.
        let before = move(&c, to: Point2D(x: 0.4, y: 0.5))!.screen.x
        let after = move(&c, to: Point2D(x: 0.6, y: 0.5))!.screen.x
        XCTAssertLessThan(after, before)
    }

    func testWithoutMirrorTheCursorFollowsTheRawImage() {
        var s = settings()
        s.mirrorCamera = false
        var c = CursorController(settings: s)
        let before = move(&c, to: Point2D(x: 0.4, y: 0.5))!.screen.x
        let after = move(&c, to: Point2D(x: 0.6, y: 0.5))!.screen.x
        XCTAssertGreaterThan(after, before)
    }

    // MARK: Screens (arbitrary, offset, logical points)

    func testArbitraryAndOffsetDisplays() {
        let displays = [
            Rect2D(x: 0, y: 0, width: 1512, height: 982),     // e.g. 14" MacBook Pro, logical points
            Rect2D(x: 1512, y: -200, width: 2560, height: 1440),
            Rect2D(x: -1920, y: 0, width: 1920, height: 1080),
        ]
        for d in displays {
            var c = CursorController(settings: settings())
            let center = move(&c, to: Point2D(x: 0.5, y: 0.5), display: d)!.screen
            XCTAssertPointEqual(center, Point2D(x: d.minX + d.width / 2, y: d.minY + d.height / 2), accuracy: 1e-6)
            c.reset()
            let topLeft = move(&c, to: raw(mirroredX: 0.15, y: 0.15), display: d)!.screen
            XCTAssertPointEqual(topLeft, Point2D(x: d.minX, y: d.minY), accuracy: 1e-6)
            c.reset()
            let bottomRight = move(&c, to: raw(mirroredX: 0.85, y: 0.85), display: d)!.screen
            XCTAssertPointEqual(bottomRight, Point2D(x: d.maxX - 1, y: d.maxY - 1), accuracy: 1e-6)
        }
    }

    func testMappingDependsOnlyOnLogicalDisplayPoints() {
        // Normalized output is independent of the display; screen output is in points of the rect
        // given (macOS reports logical points, so Retina scale never enters the math).
        var a = CursorController(settings: settings())
        var b = CursorController(settings: settings())
        let p = raw(mirroredX: 0.3, y: 0.6)
        let small = move(&a, to: p, display: Rect2D(x: 0, y: 0, width: 1512, height: 982))!
        let large = move(&b, to: p, display: Rect2D(x: 0, y: 0, width: 3024, height: 1964))!
        XCTAssertPointEqual(small.normalized, large.normalized)
        XCTAssertEqual(large.screen.x, small.screen.x * 2, accuracy: 1e-6)
    }

    func testInvalidDisplayMovesNothing() {
        var c = CursorController(settings: settings())
        XCTAssertNil(move(&c, to: Point2D(x: 0.5, y: 0.5), display: Rect2D(x: 0, y: 0, width: 0, height: 900)))
    }

    // MARK: Sensitivity, smoothing, dead zone through the controller

    func testHigherSensitivityNeedsLessHandTravel() {
        var c = CursorController(settings: settings(sensitivity: 2))
        // A quarter of the active area left of center already reaches the left edge at 2×.
        XCTAssertEqual(move(&c, to: raw(mirroredX: 0.325, y: 0.5))?.screen.x ?? -1, 0, accuracy: 1e-6)
    }

    func testSmoothingSoftensAStep() {
        var c = CursorController(settings: settings(smoothing: 0.5))
        _ = move(&c, to: raw(mirroredX: 0.15, y: 0.5)) // screen left
        let next = move(&c, to: raw(mirroredX: 0.85, y: 0.5))! // target: screen right
        XCTAssertEqual(next.normalized.x, 0.5, accuracy: 1e-9, "EMA 0.5 goes halfway")
        XCTAssertEqual(next.target.x, 1, accuracy: 1e-9)
    }

    func testDeadZoneHoldsTheCursorForMicroMovements() {
        var c = CursorController(settings: settings(deadZone: 0.01))
        let first = move(&c, to: Point2D(x: 0.5, y: 0.5))!
        // 0.004 of the image = 0.0057 of the active area < 0.01 → no movement.
        let jitter = move(&c, to: Point2D(x: 0.504, y: 0.497))!
        XCTAssertEqual(jitter.screen, first.screen)
        // 0.05 of the image ≈ 0.07 of the area → passes through.
        let real = move(&c, to: Point2D(x: 0.55, y: 0.5))!
        XCTAssertNotEqual(real.screen, first.screen)
    }

    // MARK: Primary hand

    func testOnlyThePrimaryHandMovesTheCursor() {
        var c = CursorController(settings: settings())
        let primary = TestHands.pointing(at: Point2D(x: 0.4, y: 0.5))
        let a = c.update(hands: [primary, TestHands.pointing(at: Point2D(x: 0.8, y: 0.2))], timestamp: 0, display: display, isActive: true)!
        let b = c.update(hands: [primary, TestHands.pointing(at: Point2D(x: 0.7, y: 0.8))], timestamp: 0.033, display: display, isActive: true)!
        XCTAssertEqual(a.screen, b.screen, "moving the secondary hand must not move the cursor")
    }

    // MARK: Safety: no hand, invalid input, disabled, loss, recovery

    func testNoHandMovesNothing() {
        var c = CursorController(settings: settings())
        XCTAssertNil(c.update(hands: [], timestamp: 0, display: display, isActive: true))
    }

    func testMissingOrWeakIndexTipMovesNothing() {
        var c = CursorController(settings: settings())
        let noTip = TestHands.openHand(omit: [.indexTip])
        XCTAssertNil(c.update(hands: [noTip], timestamp: 0, display: display, isActive: true))
        let weakTip = TestHands.pointing(at: Point2D(x: 0.5, y: 0.5), indexConfidence: 0.05)
        XCTAssertNil(c.update(hands: [weakTip], timestamp: 0, display: display, isActive: true))
        var nanTip = TestHands.pointing(at: Point2D(x: 0.5, y: 0.5))
        nanTip.landmarks[.indexTip]?.position = Point2D(x: .nan, y: 0.5)
        XCTAssertNil(c.update(hands: [nanTip], timestamp: 0, display: display, isActive: true))
    }

    func testDisabledControllerMovesNothingAndForgetsItsState() {
        var c = CursorController(settings: settings())
        _ = move(&c, to: Point2D(x: 0.5, y: 0.5))
        XCTAssertTrue(c.isTracking)
        XCTAssertNil(move(&c, to: Point2D(x: 0.3, y: 0.5), active: false))
        XCTAssertFalse(c.isTracking)
    }

    func testTrackingLossStopsUpdatesImmediately() {
        var c = CursorController(settings: settings(smoothing: 0.5))
        _ = move(&c, to: Point2D(x: 0.5, y: 0.5), t: 0)
        _ = move(&c, to: Point2D(x: 0.6, y: 0.5), t: 0.033)
        for i in 2..<10 {
            XCTAssertNil(c.update(hands: [], timestamp: Double(i) * 0.033, display: display, isActive: true))
        }
        XCTAssertTrue(c.needsReferencePosition, "the next valid frame must start a new session")
    }

    func testRecoveryNeverUsesStalePositions() {
        var c = CursorController(settings: settings(smoothing: 0.8))
        _ = move(&c, to: raw(mirroredX: 0.15, y: 0.15), t: 0) // top-left
        _ = c.update(hands: [], timestamp: 0.1, display: display, isActive: true)
        // Hand comes back at the bottom-right. With stale smoothing the output would be dragged
        // toward the old top-left position; it must be exactly the new target instead.
        let back = move(&c, to: raw(mirroredX: 0.85, y: 0.85), t: 0.2)!
        XCTAssertPointEqual(back.normalized, Point2D(x: 1, y: 1))
    }

    func testRecoveryStartsWhereTheCursorIsAndGlidesWithoutAJump() {
        var c = CursorController(settings: settings(blend: 0.2))
        let cursorNow = Point2D(x: 360, y: 225) // where the system cursor currently is
        let first = move(&c, to: Point2D(x: 0.5, y: 0.5), t: 1.0, cursor: cursorNow)!
        XCTAssertPointEqual(first.screen, cursorNow, accuracy: 1e-6, "no jump on (re)acquisition")
        let halfway = move(&c, to: Point2D(x: 0.5, y: 0.5), t: 1.1, cursor: nil)!
        XCTAssertPointEqual(halfway.screen, Point2D(x: 540, y: 337.5), accuracy: 1e-6)
        let done = move(&c, to: Point2D(x: 0.5, y: 0.5), t: 1.25, cursor: nil)!
        XCTAssertPointEqual(done.screen, Point2D(x: 720, y: 450), accuracy: 1e-6)
    }

    func testRecoveryWithoutReferenceGoesStraightToTheFinger() {
        var c = CursorController(settings: settings(blend: 0.2))
        XCTAssertPointEqual(move(&c, to: Point2D(x: 0.5, y: 0.5), t: 0, cursor: nil)?.screen, Point2D(x: 720, y: 450))
    }

    func testSameInputsGiveSameOutputs() {
        var a = CursorController(settings: .default)
        var b = CursorController(settings: .default)
        var generator = SeededGenerator(seed: 3)
        for i in 0..<60 {
            let p = Point2D(x: Double.random(in: 0.2...0.8, using: &generator), y: Double.random(in: 0.2...0.8, using: &generator))
            let t = Double(i) / 30
            XCTAssertEqual(move(&a, to: p, t: t, cursor: Point2D(x: 10, y: 10)), move(&b, to: p, t: t, cursor: Point2D(x: 10, y: 10)))
        }
    }

    // MARK: Activation state

    func testControlStateResolution() {
        XCTAssertEqual(CursorControlState.resolve(enabled: false, paused: false, permissionGranted: true, handAvailable: true), .off)
        XCTAssertEqual(CursorControlState.resolve(enabled: true, paused: true, permissionGranted: true, handAvailable: true), .paused)
        XCTAssertEqual(CursorControlState.resolve(enabled: true, paused: false, permissionGranted: false, handAvailable: true), .waitingForPermission)
        XCTAssertEqual(CursorControlState.resolve(enabled: true, paused: false, permissionGranted: true, handAvailable: false), .waitingForHand)
        XCTAssertEqual(CursorControlState.resolve(enabled: true, paused: false, permissionGranted: true, handAvailable: true), .active)
        XCTAssertTrue(CursorControlState.active.movesCursor)
        for state in [CursorControlState.off, .paused, .waitingForPermission, .waitingForHand] {
            XCTAssertFalse(state.movesCursor, "\(state)")
        }
    }

    // MARK: Settings

    func testDefaultCursorSettings() {
        let s = AirTrackSettings.default
        XCTAssertEqual(s.cursorSensitivity, 1)
        XCTAssertEqual(s.cursorSmoothing, 0.35)
        XCTAssertEqual(s.cursorDeadZone, 0.003)
        XCTAssertEqual(s.cursorReacquisitionBlend, 0.2)
        XCTAssertTrue(s.mirrorCamera)
        XCTAssertRectEqual(s.activeArea, Rect2D(x: 0.15, y: 0.15, width: 0.7, height: 0.7))
    }

    func testCustomActiveAreaIsUsed() {
        var c = CursorController(settings: settings(area: Rect2D(x: 0.3, y: 0.3, width: 0.4, height: 0.4)))
        XCTAssertPointEqual(move(&c, to: raw(mirroredX: 0.3, y: 0.3))?.screen, Point2D(x: 0, y: 0), accuracy: 1e-6)
    }

    func testSettingsCanChangeWhileTracking() {
        var c = CursorController(settings: settings())
        _ = move(&c, to: raw(mirroredX: 0.325, y: 0.5))
        c.apply(settings(sensitivity: 2))
        XCTAssertEqual(move(&c, to: raw(mirroredX: 0.325, y: 0.5))?.screen.x ?? -1, 0, accuracy: 1e-6)
    }

    func testOutOfRangeCursorSettingsAreSanitized() {
        var s = AirTrackSettings()
        s.cursorDeadZone = 0.5
        s.cursorReacquisitionBlend = -1
        XCTAssertEqual(s.sanitized.cursorDeadZone, DeadZoneFilter.thresholdRange.upperBound)
        XCTAssertEqual(s.sanitized.cursorReacquisitionBlend, 0)
        s.cursorDeadZone = .nan
        XCTAssertEqual(s.sanitized.cursorDeadZone, AirTrackSettings.default.cursorDeadZone)
    }
}
