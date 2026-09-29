import XCTest
@testable import AirTrackCore

/// Thresholds and offsets are dyadic (1/32, 1/64 …) and inside the allowed range (≤ 0.05),
/// so the boundary comparisons are exact.
final class DeadZoneFilterTests: XCTestCase {
    private let threshold = 0.03125 // 1/32
    func testFirstPointPassesThrough() {
        var f = DeadZoneFilter(threshold: threshold)
        XCTAssertEqual(f.apply(Point2D(x: 0.5, y: 0.5)), Point2D(x: 0.5, y: 0.5))
    }

    func testBelowThresholdHoldsTheAnchor() {
        var f = DeadZoneFilter(threshold: threshold)
        _ = f.apply(Point2D(x: 0.5, y: 0.5))
        XCTAssertEqual(f.apply(Point2D(x: 0.515625, y: 0.5)), Point2D(x: 0.5, y: 0.5)) // +1/64
    }

    func testExactlyThresholdHoldsTheAnchor() {
        var f = DeadZoneFilter(threshold: threshold)
        _ = f.apply(Point2D(x: 0.5, y: 0.5))
        XCTAssertEqual(f.apply(Point2D(x: 0.53125, y: 0.5)), Point2D(x: 0.5, y: 0.5)) // exactly +1/32
    }

    func testAboveThresholdPassesThroughAndReanchors() {
        var f = DeadZoneFilter(threshold: threshold)
        _ = f.apply(Point2D(x: 0.5, y: 0.5))
        XCTAssertEqual(f.apply(Point2D(x: 0.546875, y: 0.5)), Point2D(x: 0.546875, y: 0.5)) // +3/64
        XCTAssertEqual(f.anchor, Point2D(x: 0.546875, y: 0.5))
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
        var f = DeadZoneFilter(threshold: threshold)
        _ = f.apply(Point2D(x: 0.5, y: 0.5))
        f.reset()
        XCTAssertNil(f.anchor)
        XCTAssertEqual(f.apply(Point2D(x: 0.6, y: 0.5)), Point2D(x: 0.6, y: 0.5))
    }

    func testOversizedThresholdIsClampedSoRealMovementStillPasses() {
        var f = DeadZoneFilter(threshold: 0.25) // clamped to 0.05
        _ = f.apply(Point2D(x: 0.5, y: 0.5))
        XCTAssertEqual(f.apply(Point2D(x: 0.625, y: 0.5)), Point2D(x: 0.625, y: 0.5))
    }

    func testThresholdIsClampedSoTheCursorCannotGetStuck() {
        XCTAssertEqual(DeadZoneFilter(threshold: 1).effectiveThreshold, DeadZoneFilter.thresholdRange.upperBound)
        XCTAssertEqual(DeadZoneFilter(threshold: -1).effectiveThreshold, 0)
        XCTAssertEqual(DeadZoneFilter(threshold: .nan).effectiveThreshold, 0)
    }
}
