import XCTest
@testable import AirTrackCore

final class DeadZoneFilterTests: XCTestCase {
    func testFirstPointPassesThrough() {
        var f = DeadZoneFilter(threshold: 0.25)
        XCTAssertEqual(f.apply(Point2D(x: 0.5, y: 0.5)), Point2D(x: 0.5, y: 0.5))
    }

    func testBelowThresholdHoldsTheAnchor() {
        var f = DeadZoneFilter(threshold: 0.25)
        _ = f.apply(Point2D(x: 0.5, y: 0.5))
        XCTAssertEqual(f.apply(Point2D(x: 0.625, y: 0.5)), Point2D(x: 0.5, y: 0.5))
    }

    func testExactlyThresholdHoldsTheAnchor() {
        var f = DeadZoneFilter(threshold: 0.25)
        _ = f.apply(Point2D(x: 0.5, y: 0.5))
        XCTAssertEqual(f.apply(Point2D(x: 0.75, y: 0.5)), Point2D(x: 0.5, y: 0.5))
    }

    func testAboveThresholdPassesThroughAndReanchors() {
        var f = DeadZoneFilter(threshold: 0.25)
        _ = f.apply(Point2D(x: 0.5, y: 0.5))
        XCTAssertEqual(f.apply(Point2D(x: 0.8125, y: 0.5)), Point2D(x: 0.8125, y: 0.5))
        XCTAssertEqual(f.anchor, Point2D(x: 0.8125, y: 0.5))
    }

    func testStationaryFingerWithNoiseProducesAConstantOutput() {
        var f = DeadZoneFilter(threshold: 0.004)
        var generator = SeededGenerator(seed: 11)
        let still = Point2D(x: 0.4, y: 0.6)
        let first = f.apply(still)
        for _ in 0..<200 {
            let noisy = still + Point2D(x: Double.random(in: -0.002...0.002, using: &generator),
                                        y: Double.random(in: -0.002...0.002, using: &generator))
            XCTAssertEqual(f.apply(noisy), first)
        }
    }

    func testIntentionalMovementIsFollowedExactly() {
        var f = DeadZoneFilter(threshold: 0.004)
        _ = f.apply(Point2D(x: 0.2, y: 0.5))
        for i in 1...20 {
            let p = Point2D(x: 0.2 + Double(i) * 0.02, y: 0.5)
            XCTAssertEqual(f.apply(p), p, "a real movement must never lag")
        }
    }

    func testResetForgetsTheAnchor() {
        var f = DeadZoneFilter(threshold: 0.25)
        _ = f.apply(Point2D(x: 0.5, y: 0.5))
        f.reset()
        XCTAssertNil(f.anchor)
        XCTAssertEqual(f.apply(Point2D(x: 0.6, y: 0.5)), Point2D(x: 0.6, y: 0.5))
    }

    func testThresholdIsClampedSoTheCursorCannotGetStuck() {
        XCTAssertEqual(DeadZoneFilter(threshold: 1).effectiveThreshold, DeadZoneFilter.thresholdRange.upperBound)
        XCTAssertEqual(DeadZoneFilter(threshold: -1).effectiveThreshold, 0)
        XCTAssertEqual(DeadZoneFilter(threshold: .nan).effectiveThreshold, 0)
    }
}
