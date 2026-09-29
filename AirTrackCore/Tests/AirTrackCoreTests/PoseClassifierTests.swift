import XCTest
@testable import AirTrackCore

/// PHASE 3A-1: poses and their hysteresis.
final class PoseClassifierTests: XCTestCase {
    private func pose(_ hand: HandState, current: HandPose = .unknown) -> HandPose {
        guard let f = HandFeatureExtractor.features(of: hand) else { return .unknown }
        return PoseClassifier.classify(f, current: current)
    }

    func testCanonicalPoses() {
        XCTAssertEqual(pose(TestPoses.hand(extended: TestPoses.pointing)), .pointing)
        XCTAssertEqual(pose(TestPoses.hand(extended: TestPoses.twoFingers)), .twoFinger)
        XCTAssertEqual(pose(TestPoses.hand(extended: TestPoses.fourFingers, thumb: .extended)), .openHand)
        XCTAssertEqual(pose(TestPoses.hand(extended: TestPoses.fourFingers, thumb: .folded)), .fourFinger)
        XCTAssertEqual(pose(TestPoses.hand(extended: TestPoses.pointing, thumb: .pinching)), .pinch)
    }

    func testPosesHoldAcrossScaleRotationPositionAndAspect() {
        let cases: [(FingerSet, TestPoses.Thumb, HandPose)] = [
            (TestPoses.pointing, .folded, .pointing),
            (TestPoses.twoFingers, .folded, .twoFinger),
            (TestPoses.fourFingers, .extended, .openHand),
            (TestPoses.fourFingers, .folded, .fourFinger),
            (TestPoses.pointing, .pinching, .pinch),
        ]
        for (fingers, thumb, expected) in cases {
            for scale in [0.5, 1, 2] {
                for degrees in [-25.0, 0, 25] {
                    let hand = TestPoses.hand(extended: fingers, thumb: thumb, center: Point2D(x: 0.45, y: 0.5),
                                              scale: scale, rotation: degrees * .pi / 180, aspect: 16.0 / 9.0)
                    XCTAssertEqual(pose(hand), expected, "\(expected) scale \(scale) rotation \(degrees)")
                }
            }
        }
    }

    func testAmbiguousHandsAreUnknown() {
        // Middle bent but ring extended: no defined pose.
        XCTAssertEqual(pose(TestPoses.hand(extended: [.index, .ring])), .unknown)
        // Middle finger not measurable: neither pointing nor two fingers.
        XCTAssertEqual(pose(TestPoses.hand(extended: TestPoses.twoFingers, omit: [.middleDIP])), .unknown)
        // Fist: the folded thumb lies next to the curled index, but it is not a pinch.
        XCTAssertEqual(pose(TestPoses.hand(extended: [])), .unknown)
    }

    func testAmbiguousThumbIsNeverFourFinger() {
        XCTAssertNotEqual(pose(TestPoses.hand(extended: TestPoses.fourFingers, thumb: .uncertain)), .fourFinger)
    }

    func testThumbOnMiddleTipIsNotTwoFinger() {
        // Future right-click relation: must not be read as the scroll pose.
        XCTAssertEqual(pose(TestPoses.hand(extended: TestPoses.twoFingers, thumb: .touchingMiddle)), .unknown)
    }

    func testPinchHysteresisBand() {
        var hand = TestPoses.hand(extended: TestPoses.pointing, thumb: .pinching)
        // Open the pinch to 0.3 hand scales: inside the band (enter 0.25, exit 0.35).
        let index = hand.landmarks[.indexTip]!.position
        hand.landmarks[.thumbTip]?.position = index + Point2D(x: 0.3 * 0.135, y: 0)
        XCTAssertEqual(pose(hand, current: .pinch), .pinch, "stays pinched inside the band")
        XCTAssertNotEqual(pose(hand, current: .pointing), .pinch, "does not start a pinch inside the band")
    }

    func testOneNoisyFrameDoesNotChangeTheStablePose() {
        var classifier = PoseClassifier()
        let two = HandFeatureExtractor.features(of: TestPoses.hand(extended: TestPoses.twoFingers))!
        let point = HandFeatureExtractor.features(of: TestPoses.hand(extended: TestPoses.pointing))!
        classifier.update(two)
        XCTAssertEqual(classifier.update(two), .twoFinger)
        XCTAssertEqual(classifier.update(point), .twoFinger, "one frame is not enough")
        XCTAssertEqual(classifier.rawPose, .pointing)
        XCTAssertEqual(classifier.update(two), .twoFinger)
        XCTAssertEqual(classifier.update(point), .twoFinger)
        XCTAssertEqual(classifier.update(point), .pointing, "two consecutive frames change it")
    }

    func testFlickeringInputNeverSettlesOnAWrongPose() {
        var classifier = PoseClassifier()
        let two = HandFeatureExtractor.features(of: TestPoses.hand(extended: TestPoses.twoFingers))!
        let point = HandFeatureExtractor.features(of: TestPoses.hand(extended: TestPoses.pointing))!
        for _ in 0..<3 { classifier.update(two) }
        for i in 0..<20 {
            XCTAssertEqual(classifier.update(i.isMultiple(of: 2) ? point : two), .twoFinger)
        }
    }

    func testNoFeaturesMeansUnknownImmediately() {
        var classifier = PoseClassifier()
        let two = HandFeatureExtractor.features(of: TestPoses.hand(extended: TestPoses.twoFingers))!
        classifier.update(two)
        classifier.update(two)
        XCTAssertEqual(classifier.update(nil), .unknown)
    }
}
