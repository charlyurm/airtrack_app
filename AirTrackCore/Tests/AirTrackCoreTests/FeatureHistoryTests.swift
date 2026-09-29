import XCTest
@testable import AirTrackCore

/// PHASE 3A-1: bounded temporal history, motion in user space and hand-scale units.
final class FeatureHistoryTests: XCTestCase {
    private let dt = 1.0 / 30

    private func features(at t: TimeInterval, center: Point2D, scale: Double = 1, aspect: Double = 1) -> HandFeatures {
        HandFeatureExtractor.features(of: TestPoses.hand(extended: TestPoses.twoFingers, at: t, center: center, scale: scale, aspect: aspect))!
    }

    func testRingBufferIsBoundedAndOrdered() {
        var buffer = RingBuffer<Int>(capacity: 4)
        for i in 0..<10 { buffer.append(i) }
        XCTAssertEqual(buffer.count, 4)
        XCTAssertEqual(buffer.elements, [6, 7, 8, 9])
        XCTAssertEqual(buffer.last, 9)
        buffer.removeAll()
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertNil(buffer.last)
    }

    func testHistoryNeverExceedsItsWindowOrCapacity() {
        var history = FeatureHistory(window: 0.5, capacity: 32)
        for i in 0..<300 {
            history.append(features(at: Double(i) * dt, center: Point2D(x: 0.5, y: 0.5)), pose: .twoFinger, mirrored: true)
            XCTAssertLessThanOrEqual(history.count, 32)
            if let first = history.all.first, let last = history.latest {
                XCTAssertLessThanOrEqual(last.time - first.time, 0.5 + 1e-9)
            }
        }
    }

    func testVelocityAndDisplacementAreInHandScalesPerSecond() {
        var history = FeatureHistory()
        // 0.0135 image heights per frame down = 0.1 hand scales per frame = 3 scales/s.
        for i in 0..<10 {
            history.append(features(at: Double(i) * dt, center: Point2D(x: 0.5, y: 0.3 + 0.0135 * Double(i))), pose: .twoFinger, mirrored: true)
        }
        let v = history.velocity(over: 0.1)
        XCTAssertEqual(v.dy, 3, accuracy: 1e-6)
        XCTAssertEqual(v.dx, 0, accuracy: 1e-9)
        XCTAssertEqual(history.displacement(since: 0).dy, 0.9, accuracy: 1e-6)
        let step = history.lastStep()!
        XCTAssertEqual(step.motion.dy, 0.1, accuracy: 1e-6)
        XCTAssertEqual(step.dt, dt, accuracy: 1e-9)
    }

    func testSameMotionIsTheSameAtAnyDistance() {
        for scale in [0.5, 1, 2] {
            var history = FeatureHistory()
            for i in 0..<6 {
                // One hand scale of movement over 5 frames, whatever the hand's size.
                let y = 0.3 + 0.135 * scale * Double(i) / 5
                history.append(features(at: Double(i) * dt, center: Point2D(x: 0.5, y: y), scale: scale), pose: .twoFinger, mirrored: true)
            }
            XCTAssertEqual(history.displacement(since: 0).dy, 1, accuracy: 1e-6, "scale \(scale)")
        }
    }

    func testHorizontalMotionIsInTheUsersViewAndAspectCorrected() {
        var mirrored = FeatureHistory()
        var raw = FeatureHistory()
        for i in 0..<4 {
            // The hand moves to the RIGHT of the raw image = the user's LEFT (mirror on).
            let f = features(at: Double(i) * dt, center: Point2D(x: 0.4 + 0.01 * Double(i), y: 0.5), aspect: 16.0 / 9.0)
            mirrored.append(f, pose: .twoFinger, mirrored: true)
            raw.append(f, pose: .twoFinger, mirrored: false)
        }
        XCTAssertLessThan(mirrored.displacement(since: 0).dx, 0)
        XCTAssertGreaterThan(raw.displacement(since: 0).dx, 0)
        XCTAssertEqual(raw.displacement(since: 0).dx, 0.03 * 16 / 9 / 0.135, accuracy: 1e-6)
    }

    func testOutOfOrderSamplesRestartTheTimeline() {
        var history = FeatureHistory()
        history.append(features(at: 1.0, center: Point2D(x: 0.5, y: 0.5)), pose: .twoFinger, mirrored: true)
        history.append(features(at: 1.1, center: Point2D(x: 0.5, y: 0.6)), pose: .twoFinger, mirrored: true)
        history.append(features(at: 0.5, center: Point2D(x: 0.5, y: 0.4)), pose: .twoFinger, mirrored: true)
        XCTAssertEqual(history.count, 1, "stale timeline dropped")
        XCTAssertEqual(history.displacement(since: 0), .zero)
    }

    func testDominantAxis() {
        XCTAssertEqual(DominantAxis.of(MotionVector(dx: 0.01, dy: 0.2), minimumMagnitude: 0.04, ratio: 2), .vertical)
        XCTAssertEqual(DominantAxis.of(MotionVector(dx: -0.3, dy: 0.05), minimumMagnitude: 0.04, ratio: 2), .horizontal)
        XCTAssertEqual(DominantAxis.of(MotionVector(dx: 0.2, dy: -0.2), minimumMagnitude: 0.04, ratio: 2), .ambiguous)
        XCTAssertEqual(DominantAxis.of(MotionVector(dx: 0.01, dy: 0.01), minimumMagnitude: 0.04, ratio: 2), .none)
        XCTAssertEqual(DominantAxis.of(MotionVector(dx: .nan, dy: 1), minimumMagnitude: 0.04, ratio: 2), .none)
    }
}
