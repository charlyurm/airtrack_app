import XCTest
@testable import AirTrackCore

final class HandPresenceFilterTests: XCTestCase {
    private func filter(framesToAcquire: Int = 2) -> HandPresenceFilter {
        HandPresenceFilter(configuration: HandFilterConfiguration(framesToAcquire: framesToAcquire))
    }

    private let left = TestHands.openHand(center: Point2D(x: 0.3, y: 0.5), chirality: .right)
    private let right = TestHands.openHand(center: Point2D(x: 0.7, y: 0.5), chirality: .left)

    // MARK: Hand count

    func testZeroHands() {
        var f = filter(framesToAcquire: 1)
        XCTAssertEqual(f.update(candidates: []), [])
    }

    func testOneHand() {
        var f = filter(framesToAcquire: 1)
        XCTAssertEqual(f.update(candidates: [left]).count, 1)
    }

    func testTwoHandsAreBothReportedInDeterministicOrder() {
        var f = filter(framesToAcquire: 1)
        let a = f.update(candidates: [right, left])
        let b = f.update(candidates: [left, right])
        XCTAssertEqual(a.count, 2, "the second hand must not be dropped")
        XCTAssertEqual(a, b, "order must not depend on the provider's result order")
        XCTAssertEqual(a.first?.chirality, .right) // the one at x = 0.3
    }

    func testAtMostTwoHands() {
        var f = filter(framesToAcquire: 1)
        let third = TestHands.openHand(center: Point2D(x: 0.5, y: 0.5))
        XCTAssertEqual(f.update(candidates: [left, right, third]).count, 2)
    }

    // MARK: Validation / false positives

    func testLowHandConfidenceIsNotAHand() {
        let weak = TestHands.openHand(handConfidence: 0.1)
        XCTAssertEqual(HandValidation.validate(weak, configuration: .init()), .failure(.lowHandConfidence))
    }

    func testLowConfidenceJointsAreRemovedNotKept() {
        var hand = TestHands.openHand()
        hand.landmarks[.pinkyTip]?.confidence = 0.05
        guard case let .success(cleaned) = HandValidation.validate(hand, configuration: .init()) else {
            return XCTFail("hand with one weak joint should still be valid")
        }
        XCTAssertNil(cleaned.landmarks[.pinkyTip])
        XCTAssertEqual(cleaned.landmarks.count, 20)
    }

    func testMissingRequiredJointRejectsTheHand() {
        let hand = TestHands.openHand(omit: [.indexTip])
        XCTAssertEqual(HandValidation.validate(hand, configuration: .init()), .failure(.missingRequiredJoint(.indexTip)))
    }

    func testRequiredJointWithLowConfidenceRejectsTheHand() {
        var hand = TestHands.openHand()
        hand.landmarks[.thumbTip]?.confidence = 0.1
        XCTAssertEqual(HandValidation.validate(hand, configuration: .init()), .failure(.missingRequiredJoint(.thumbTip)))
    }

    func testPartialDetectionWithTooFewJointsIsRejected() {
        let keep: Set<HandJoint> = [.wrist, .thumbTip, .indexMCP, .indexTip, .middleTip]
        let hand = TestHands.openHand(omit: Set(HandJoint.allCases).subtracting(keep))
        XCTAssertEqual(HandValidation.validate(hand, configuration: .init()), .failure(.tooFewJoints(5)))
    }

    func testTinySpuriousHandIsRejected() {
        let hand = TestHands.openHand(scale: 0.1) // wrist→indexMCP ≈ 0.013 < 0.02
        XCTAssertEqual(HandValidation.validate(hand, configuration: .init()), .failure(.handTooSmall))
    }

    func testJointsFarOutsideTheImageAreRemoved() {
        var hand = TestHands.openHand()
        hand.landmarks[.pinkyTip]?.position = Point2D(x: 1.4, y: 0.5)
        guard case let .success(cleaned) = HandValidation.validate(hand, configuration: .init()) else {
            return XCTFail("expected a valid hand")
        }
        XCTAssertNil(cleaned.landmarks[.pinkyTip])
    }

    func testInvalidProviderValuesNeverBecomeAHand() {
        var nanConfidence = TestHands.openHand()
        nanConfidence.confidence = .nan
        XCTAssertEqual(HandValidation.validate(nanConfidence, configuration: .init()), .failure(.lowHandConfidence))

        var nanWrist = TestHands.openHand()
        nanWrist.landmarks[.wrist]?.position = Point2D(x: .nan, y: 0.5)
        XCTAssertEqual(HandValidation.validate(nanWrist, configuration: .init()), .failure(.missingRequiredJoint(.wrist)))

        XCTAssertEqual(HandValidation.validate(.untracked(at: 0), configuration: .init()), .failure(.missingRequiredJoint(.wrist)))
    }

    func testSingleFrameFalsePositiveIsNeverReported() {
        var f = filter()
        let weak = TestHands.openHand(handConfidence: 0.1)
        // A valid-looking hand that appears for one frame at a time, never twice in a row.
        for _ in 0..<5 {
            XCTAssertEqual(f.update(candidates: [left]), [])
            XCTAssertEqual(f.update(candidates: [weak]), [])
        }
    }

    func testRejectionReasonsAreReported() {
        var f = filter(framesToAcquire: 1)
        _ = f.update(candidates: [left, TestHands.openHand(handConfidence: 0.1)])
        XCTAssertEqual(f.lastRejections, [.lowHandConfidence])
    }

    // MARK: Loss, recovery and stale data

    func testAcquisitionNeedsConsecutiveFrames() {
        var f = filter()
        XCTAssertEqual(f.update(candidates: [left]), [])
        XCTAssertEqual(f.update(candidates: [left]).count, 1)
    }

    func testTrackingLossIsImmediate() {
        var f = filter()
        _ = f.update(candidates: [left])
        _ = f.update(candidates: [left])
        XCTAssertEqual(f.update(candidates: []), [])
    }

    func testFailedObservationNeverReusesTheLastHand() {
        var f = filter()
        _ = f.update(candidates: [left])
        XCTAssertEqual(f.update(candidates: [left]).count, 1)
        // Next frame the provider returns garbage: no hand, and certainly not the old one.
        XCTAssertEqual(f.update(candidates: [TestHands.openHand(handConfidence: 0.05)]), [])
        XCTAssertEqual(f.update(candidates: [.untracked(at: 1)]), [])
    }

    func testOutputAlwaysComesFromTheCurrentFrame() {
        var f = filter(framesToAcquire: 1)
        let first = TestHands.openHand(at: 1, center: Point2D(x: 0.3, y: 0.5))
        let second = TestHands.openHand(at: 2, center: Point2D(x: 0.6, y: 0.4))
        _ = f.update(candidates: [first])
        let out = f.update(candidates: [second])
        XCTAssertEqual(out.first?.timestamp, 2)
        XCTAssertPointEqual(out.first?.position(of: .wrist), Point2D(x: 0.6, y: 0.55))
    }

    func testRecoveryAfterLossNeedsReacquisition() {
        var f = filter()
        _ = f.update(candidates: [left])
        _ = f.update(candidates: [left])
        _ = f.update(candidates: [])
        XCTAssertEqual(f.update(candidates: [left]), [], "one frame is not enough to recover")
        XCTAssertEqual(f.update(candidates: [left]).count, 1)
    }
}
