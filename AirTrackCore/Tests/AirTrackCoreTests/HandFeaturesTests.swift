import XCTest
@testable import AirTrackCore

/// PHASE 3A-1: normalized hand features and finger states.
final class HandFeaturesTests: XCTestCase {
    private func features(_ hand: HandState) -> HandFeatures {
        guard let f = HandFeatureExtractor.features(of: hand) else {
            XCTFail("hand should be measurable")
            return HandFeatureExtractor.features(of: TestPoses.hand(extended: TestPoses.fourFingers, thumb: .extended))!
        }
        return f
    }

    private func states(_ f: HandFeatures) -> [FingerState] {
        Finger.allCases.map { f.state(of: $0) }
    }

    // MARK: Scale and normalization

    func testScaleIsProportionalToHandSize() {
        for size in [0.5, 1.0, 2.0] {
            let f = features(TestPoses.hand(extended: TestPoses.fourFingers, thumb: .extended, scale: size))
            XCTAssertEqual(f.scale, 0.135 * size, accuracy: 1e-9, "scale \(size)")
        }
    }

    func testNormalizedDistancesDoNotDependOnSizePositionOrAspect() {
        let reference = features(TestPoses.hand(extended: TestPoses.twoFingers))
        let variants = [
            TestPoses.hand(extended: TestPoses.twoFingers, scale: 0.5),
            TestPoses.hand(extended: TestPoses.twoFingers, scale: 2),
            TestPoses.hand(extended: TestPoses.twoFingers, center: Point2D(x: 0.3, y: 0.6)),
            TestPoses.hand(extended: TestPoses.twoFingers, aspect: 16.0 / 9.0),
        ]
        for hand in variants {
            let f = features(hand)
            XCTAssertEqual(f.thumbIndexDistance!, reference.thumbIndexDistance!, accuracy: 1e-9)
            XCTAssertEqual(f.thumbMiddleDistance!, reference.thumbMiddleDistance!, accuracy: 1e-9)
            XCTAssertEqual(f.indexMiddleDistance!, reference.indexMiddleDistance!, accuracy: 1e-9)
            XCTAssertEqual(states(f), states(reference))
        }
    }

    func testRotationKeepsDistancesAndFingerStates() {
        let reference = features(TestPoses.hand(extended: TestPoses.twoFingers))
        for degrees in [-30.0, -15, 15, 30] {
            let f = features(TestPoses.hand(extended: TestPoses.twoFingers, rotation: degrees * .pi / 180))
            XCTAssertEqual(f.scale, reference.scale, accuracy: 1e-9)
            XCTAssertEqual(f.thumbIndexDistance!, reference.thumbIndexDistance!, accuracy: 1e-9)
            XCTAssertEqual(states(f), states(reference), "\(degrees)°")
        }
    }

    func testPalmCenterIsTheMeanOfTheKnuckles() {
        let f = features(TestPoses.hand(extended: TestPoses.fourFingers, thumb: .extended))
        XCTAssertPointEqual(f.palmCenter, Point2D(x: 0.5 + 0.01375, y: 0.5 + 0.0225), accuracy: 1e-9)
    }

    // MARK: Finger states

    func testOpenHandHasFiveExtendedFingers() {
        let f = features(TestPoses.hand(extended: TestPoses.fourFingers, thumb: .extended))
        XCTAssertEqual(states(f), [.extended, .extended, .extended, .extended, .extended])
        XCTAssertEqual(f.extendedCount, 5)
    }

    func testPointingHandStates() {
        let f = features(TestPoses.hand(extended: TestPoses.pointing))
        XCTAssertEqual(states(f), [.bent, .extended, .bent, .bent, .bent])
        XCTAssertEqual(f.extendedFingers, [.index])
    }

    func testMixedStatesKeepFingerIdentity() {
        let f = features(TestPoses.hand(extended: [.index, .ring], thumb: .extended))
        XCTAssertEqual(states(f), [.extended, .extended, .bent, .extended, .bent])
        XCTAssertEqual(f.extendedFingers, [.thumb, .index, .ring])
        XCTAssertEqual(f.bentFingers, [.middle, .pinky])
    }

    func testUncertainThumbStaysUnknown() {
        let f = features(TestPoses.hand(extended: TestPoses.fourFingers, thumb: .uncertain))
        XCTAssertEqual(f.state(of: .thumb), .unknown)
    }

    func testFingerPointingAtTheCameraIsUnknownNotExtended() {
        // Foreshortened index: straight but very short in the image.
        var hand = TestPoses.hand(extended: TestPoses.pointing)
        let mcp = hand.landmarks[.indexMCP]!.position
        for (joint, factor) in [(HandJoint.indexPIP, 0.15), (.indexDIP, 0.25), (.indexTip, 0.35)] {
            let p = hand.landmarks[joint]!.position
            hand.landmarks[joint]?.position = mcp + (p - mcp) * factor
        }
        XCTAssertEqual(features(hand).state(of: .index), .unknown)
    }

    func testMissingOrLowConfidenceJointsMakeTheFingerUnknown() {
        let missing = features(TestPoses.hand(extended: TestPoses.twoFingers, omit: [.middleDIP]))
        XCTAssertEqual(missing.state(of: .middle), .unknown)
        XCTAssertEqual(missing.state(of: .index), .extended)

        var weak = TestPoses.hand(extended: TestPoses.twoFingers)
        weak.landmarks[.ringTip]?.confidence = 0.1
        let f = features(weak)
        XCTAssertEqual(f.state(of: .ring), .unknown)
        XCTAssertEqual(f.fingers[.ring]?.confidence ?? -1, 0.1, accuracy: 1e-12)
    }

    func testReproducibleNoiseDoesNotChangeTheStates() {
        var generator = SeededGenerator(seed: 42)
        let expected = states(features(TestPoses.hand(extended: TestPoses.twoFingers)))
        for i in 0..<50 {
            let hand = TestPoses.hand(extended: TestPoses.twoFingers, at: Double(i), noise: 0.002, generator: &generator)
            XCTAssertEqual(states(features(hand)), expected, "sample \(i)")
        }
    }

    func testUnmeasurableHandsGiveNoFeatures() {
        XCTAssertNil(HandFeatureExtractor.features(of: HandState(timestamp: 0)))
        // No wrist and no palm width: no scale.
        let noScale = TestPoses.hand(extended: TestPoses.fourFingers, thumb: .extended, omit: [.wrist, .pinkyMCP])
        XCTAssertNil(HandFeatureExtractor.features(of: noScale))
        // Tiny, degenerate detection.
        XCTAssertNil(HandFeatureExtractor.features(of: TestPoses.hand(extended: TestPoses.fourFingers, thumb: .extended, scale: 0.05)))
    }

    func testNonFiniteValuesNeverLeak() {
        var hand = TestPoses.hand(extended: TestPoses.twoFingers)
        hand.landmarks[.indexTip]?.position = Point2D(x: .nan, y: 0.2)
        hand.landmarks[.middleMCP]?.position = Point2D(x: .infinity, y: 0.5)
        let f = features(hand)
        XCTAssertTrue(f.scale.isFinite)
        XCTAssertTrue(f.palmCenter.isFinite)
        XCTAssertEqual(f.state(of: .index), .unknown)
        XCTAssertNil(f.thumbIndexDistance)
        for finger in Finger.allCases {
            if let length = f.fingers[finger]?.length { XCTAssertTrue(length.isFinite) }
        }
    }
}
