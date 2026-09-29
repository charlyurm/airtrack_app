import XCTest
@testable import AirTrackCore

/// PHASE 3A-1: PointerTracker exposes the hand it followed, without changing its decisions.
final class PointerTrackerTrackedHandTests: XCTestCase {
    private let dt = 1.0 / 30

    private func full(_ tip: Point2D, _ t: TimeInterval) -> HandState {
        TestHands.openHand(at: t, center: tip - TestHands.openHandOffsets[.indexTip]!)
    }

    func testTrackedHandFollowsTheModes() {
        var tracker = PointerTracker()
        let tip = Point2D(x: 0.5, y: 0.5)
        XCTAssertNil(tracker.update(candidates: [full(tip, 0)], timestamp: 0).trackedHand, "not acquired yet")
        let acquired = tracker.update(candidates: [full(tip, dt)], timestamp: dt)
        XCTAssertEqual(acquired.pointer.mode, .full)
        XCTAssertEqual(acquired.trackedHand?.timestamp, dt)
        XCTAssertEqual(acquired.trackedHand, acquired.hands.first, "FULL: the strict primary hand")

        let hold = tracker.update(candidates: [], timestamp: 2 * dt)
        XCTAssertEqual(hold.pointer.mode, .holding)
        XCTAssertNil(hold.trackedHand, "HOLD: no fresh landmarks")

        // Continuation after the gap (gate bypass): hands is empty but the hand is tracked.
        let back = tracker.update(candidates: [full(tip, 3 * dt)], timestamp: 3 * dt)
        XCTAssertEqual(back.pointer.mode, .full)
        XCTAssertTrue(back.hands.isEmpty)
        XCTAssertEqual(back.trackedHand?.timestamp, 3 * dt)

        var partial = full(tip, 4 * dt)
        for joint in [HandJoint.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip, .indexMCP, .middleMCP, .ringMCP, .pinkyMCP, .pinkyPIP] {
            partial.landmarks[joint] = nil
        }
        let degraded = tracker.update(candidates: [partial], timestamp: 4 * dt)
        XCTAssertEqual(degraded.pointer.mode, .partial)
        XCTAssertNotNil(degraded.trackedHand)
        XCTAssertEqual(degraded.trackedHand?.landmarks[.wrist], nil, "the degraded observation, as seen")

        for i in 5..<15 { _ = tracker.update(candidates: [], timestamp: Double(i) * dt) }
        let lost = tracker.update(candidates: [], timestamp: 15 * dt)
        XCTAssertEqual(lost.pointer.mode, .lost)
        XCTAssertNil(lost.trackedHand)
    }

    func testTrackedHandDoesNotChangePointerDecisions() {
        // Same sequence, compare pointer decisions with the Phase 2.1 expectations.
        var tracker = PointerTracker()
        let tip = Point2D(x: 0.4, y: 0.5)
        let modes = (0..<6).map { i in tracker.update(candidates: [full(tip, Double(i) * dt)], timestamp: Double(i) * dt).pointer.mode }
        XCTAssertEqual(modes, [.lost, .full, .full, .full, .full, .full])
    }
}
