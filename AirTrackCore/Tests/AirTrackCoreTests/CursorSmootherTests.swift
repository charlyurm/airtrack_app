import XCTest
@testable import AirTrackCore

final class CursorSmootherTests: XCTestCase {
    func testFirstSampleIsPassedThrough() {
        var smoother = CursorSmoother(smoothing: 0.8)
        XCTAssertPointEqual(smoother.smooth(Point2D(x: 0.3, y: 0.7)), Point2D(x: 0.3, y: 0.7))
    }

    func testZeroSmoothingIsIdentity() {
        var smoother = CursorSmoother(smoothing: 0)
        _ = smoother.smooth(Point2D(x: 0, y: 0))
        XCTAssertPointEqual(smoother.smooth(Point2D(x: 1, y: 1)), Point2D(x: 1, y: 1))
    }

    func testExponentialMovingAverageFormula() {
        var smoother = CursorSmoother(smoothing: 0.25)
        _ = smoother.smooth(Point2D(x: 0, y: 0))
        // previous * 0.25 + current * 0.75
        XCTAssertPointEqual(smoother.smooth(Point2D(x: 1, y: 0.4)), Point2D(x: 0.75, y: 0.3))
    }

    func testConvergesToAStillTarget() {
        var smoother = CursorSmoother(smoothing: 0.5)
        _ = smoother.smooth(Point2D(x: 0, y: 0))
        var last = Point2D.zero
        for _ in 0..<20 { last = smoother.smooth(Point2D(x: 1, y: 1)) }
        XCTAssertPointEqual(last, Point2D(x: 1, y: 1), accuracy: 1e-5)
    }

    func testReducesJitter() {
        var smoother = CursorSmoother(smoothing: 0.5)
        var maxDeviation = 0.0
        for i in 0..<60 {
            let noisy = Point2D(x: 0.5 + (i.isMultiple(of: 2) ? 0.01 : -0.01), y: 0.5)
            let out = smoother.smooth(noisy)
            if i > 10 { maxDeviation = max(maxDeviation, abs(out.x - 0.5)) }
        }
        XCTAssertLessThan(maxDeviation, 0.01)
    }

    func testResetDropsHistory() {
        var smoother = CursorSmoother(smoothing: 0.9)
        _ = smoother.smooth(Point2D(x: 0, y: 0))
        smoother.reset()
        XCTAssertNil(smoother.current)
        XCTAssertPointEqual(smoother.smooth(Point2D(x: 1, y: 1)), Point2D(x: 1, y: 1))
    }

    func testStationaryInputStaysExactlyStill() {
        var smoother = CursorSmoother(smoothing: 0.35)
        let p = Point2D(x: 0.3, y: 0.7)
        for _ in 0..<30 { XCTAssertEqual(smoother.smooth(p), p) }
    }

    func testStepResponseNeverOvershoots() {
        var smoother = CursorSmoother(smoothing: 0.35)
        _ = smoother.smooth(Point2D(x: 0, y: 1))
        var previous = 0.0
        for _ in 0..<40 {
            let out = smoother.smooth(Point2D(x: 1, y: 0))
            XCTAssertGreaterThanOrEqual(out.x, previous, "must approach monotonically")
            XCTAssertLessThanOrEqual(out.x, 1, "must never pass the target")
            XCTAssertGreaterThanOrEqual(out.y, 0)
            previous = out.x
        }
    }

    func testIntentionalMovementIsFollowedWithBoundedLag() {
        // Constant-speed movement: the EMA lags by a fixed amount, it never falls further behind.
        var smoother = CursorSmoother(smoothing: 0.35)
        var lag = 0.0
        for i in 0..<60 {
            let target = Double(i) * 0.01
            lag = target - smoother.smooth(Point2D(x: target, y: 0)).x
        }
        // Steady-state lag = step · alpha / (1 − alpha) = 0.01 · 0.35 / 0.65 ≈ 0.0054.
        XCTAssertEqual(lag, 0.01 * 0.35 / 0.65, accuracy: 1e-6)
    }

    func testSameInputGivesSameOutput() {
        var a = CursorSmoother(smoothing: 0.35)
        var b = CursorSmoother(smoothing: 0.35)
        for i in 0..<20 {
            let p = Point2D(x: Double(i % 7) / 7, y: Double(i % 3) / 3)
            XCTAssertEqual(a.smooth(p), b.smooth(p))
        }
    }

    func testSmoothingIsClampedSoTheCursorNeverFreezes() {
        var smoother = CursorSmoother(smoothing: 1.0)
        XCTAssertEqual(smoother.effectiveSmoothing, CursorSmoother.smoothingRange.upperBound)
        _ = smoother.smooth(Point2D(x: 0, y: 0))
        XCTAssertGreaterThan(smoother.smooth(Point2D(x: 1, y: 0)).x, 0)

        XCTAssertEqual(CursorSmoother(smoothing: -1).effectiveSmoothing, 0)
        XCTAssertEqual(CursorSmoother(smoothing: .nan).effectiveSmoothing, 0)
    }
}
