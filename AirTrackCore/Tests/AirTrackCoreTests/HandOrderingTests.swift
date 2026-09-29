import XCTest
@testable import AirTrackCore

final class HandOrderingTests: XCTestCase {
    private func hand(x: Double, y: Double = 0.5, chirality: HandChirality = .unknown, omit: Set<HandJoint> = []) -> HandState {
        TestHands.openHand(center: Point2D(x: x, y: y), chirality: chirality, omit: omit)
    }

    func testZeroHands() {
        XCTAssertEqual(HandOrdering.ordered([]), [])
    }

    func testOneHand() {
        let h = hand(x: 0.5)
        XCTAssertEqual(HandOrdering.ordered([h]), [h])
    }

    func testTwoHandsAreOrderedLeftToRightInTheRawImage() {
        let a = hand(x: 0.2, chirality: .right)
        let b = hand(x: 0.8, chirality: .left)
        XCTAssertEqual(HandOrdering.ordered([b, a]), [a, b])
        XCTAssertEqual(HandOrdering.ordered([a, b]), [a, b])
    }

    func testSameColumnIsOrderedTopFirst() {
        let high = hand(x: 0.5, y: 0.3)
        let low = hand(x: 0.5, y: 0.7)
        XCTAssertEqual(HandOrdering.ordered([low, high]), [high, low])
    }

    func testHandWithoutWristIsPlacedByItsCentroid() {
        let noWrist = hand(x: 0.2, omit: [.wrist])
        let other = hand(x: 0.6)
        let ordered = HandOrdering.ordered([other, noWrist])
        XCTAssertEqual(ordered.count, 2)
        XCTAssertNil(ordered.first?.landmarks[.wrist], "the wrist-less hand at x≈0.2 must come first")
    }

    func testUntrackedHandsAreDropped() {
        let h = hand(x: 0.5)
        XCTAssertEqual(HandOrdering.ordered([.untracked(at: 0), h]), [h])
    }
}
