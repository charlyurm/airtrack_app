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

    func testSmoothingIsClampedSoTheCursorNeverFreezes() {
        var smoother = CursorSmoother(smoothing: 1.0)
        XCTAssertEqual(smoother.effectiveSmoothing, CursorSmoother.smoothingRange.upperBound)
        _ = smoother.smooth(Point2D(x: 0, y: 0))
        XCTAssertGreaterThan(smoother.smooth(Point2D(x: 1, y: 0)).x, 0)

        XCTAssertEqual(CursorSmoother(smoothing: -1).effectiveSmoothing, 0)
        XCTAssertEqual(CursorSmoother(smoothing: .nan).effectiveSmoothing, 0)
    }
}
