import XCTest
@testable import AirTrackCore

final class PinchRecognizerTests: XCTestCase {
    private let config = PinchConfiguration(
        startRatio: 0.25,
        releaseRatio: 0.35,
        startConfirmationFrames: 2,
        releaseConfirmationFrames: 2,
        maxUnmeasurableFrames: 3,
        minimumConfidence: 0.3
    )

    private func feed(_ recognizer: inout PinchRecognizer, ratios: [Double], scale: Double = 1) -> [PinchReading] {
        ratios.enumerated().map { i, ratio in
            recognizer.update(with: TestHands.hand(at: Double(i) / 30, pinchRatio: ratio, scale: scale))
        }
    }

    func testPinchDetectedAfterConfirmationFrames() {
        var recognizer = PinchRecognizer(configuration: config)
        let readings = feed(&recognizer, ratios: [0.1, 0.1, 0.1])
        XCTAssertEqual(readings.map(\.isPinched), [false, true, true])
        XCTAssertEqual(readings.map(\.transition), [.none, .began, .none])
    }

    func testPinchNotDetectedWhenFingersApart() {
        var recognizer = PinchRecognizer(configuration: config)
        let readings = feed(&recognizer, ratios: Array(repeating: 0.6, count: 30))
        XCTAssertTrue(readings.allSatisfy { !$0.isPinched && $0.transition == .none })
    }

    func testRatioIsInvariantToHandScale() {
        let near = TestHands.hand(at: 0, pinchRatio: 0.2, scale: 2.0)
        let far = TestHands.hand(at: 0, pinchRatio: 0.2, scale: 0.5)
        XCTAssertEqual(PinchRecognizer.pinchRatio(for: near) ?? -1, 0.2, accuracy: 1e-9)
        XCTAssertEqual(PinchRecognizer.pinchRatio(for: far) ?? -1, 0.2, accuracy: 1e-9)

        // The absolute distance differs 4x, which is why a fixed 0.045 threshold fails.
        let nearAbsolute = near.aspectCorrectedDistance(from: .thumbTip, to: .indexTip) ?? 0
        let farAbsolute = far.aspectCorrectedDistance(from: .thumbTip, to: .indexTip) ?? 0
        XCTAssertEqual(nearAbsolute / farAbsolute, 4, accuracy: 1e-9)
    }

    func testSameGestureBehavesTheSameNearAndFar() {
        let ratios = [0.6, 0.6, 0.15, 0.15, 0.15, 0.6, 0.6]
        var near = PinchRecognizer(configuration: config)
        var far = PinchRecognizer(configuration: config)
        let nearReadings = feed(&near, ratios: ratios, scale: 2.5)
        let farReadings = feed(&far, ratios: ratios, scale: 0.4)
        XCTAssertEqual(nearReadings.map(\.transition), farReadings.map(\.transition))
        XCTAssertEqual(nearReadings.map(\.transition), [.none, .none, .none, .began, .none, .none, .ended])
    }

    func testHysteresisHoldsPinchInsideTheBand() {
        var recognizer = PinchRecognizer(configuration: config)
        _ = feed(&recognizer, ratios: [0.1, 0.1])
        XCTAssertTrue(recognizer.isPinched)
        // 0.3 is above start (0.25) but below release (0.35): must stay pinched.
        let readings = feed(&recognizer, ratios: Array(repeating: 0.3, count: 20))
        XCTAssertTrue(readings.allSatisfy { $0.isPinched && $0.transition == .none })
    }

    func testHysteresisDoesNotStartPinchInsideTheBand() {
        var recognizer = PinchRecognizer(configuration: config)
        let readings = feed(&recognizer, ratios: Array(repeating: 0.3, count: 20))
        XCTAssertTrue(readings.allSatisfy { !$0.isPinched })
    }

    func testReleaseRequiresConfirmation() {
        var recognizer = PinchRecognizer(configuration: config)
        _ = feed(&recognizer, ratios: [0.1, 0.1])
        let readings = feed(&recognizer, ratios: [0.5, 0.5])
        XCTAssertEqual(readings.map(\.transition), [.none, .ended])
        XCTAssertFalse(recognizer.isPinched)
    }

    func testSingleFrameSpikesAreIgnored() {
        var recognizer = PinchRecognizer(configuration: config)
        // Open hand with a one-frame dip must not start a pinch.
        var readings = feed(&recognizer, ratios: [0.6, 0.1, 0.6, 0.1, 0.6])
        XCTAssertTrue(readings.allSatisfy { !$0.isPinched })

        // Pinched hand with a one-frame spike must not release.
        _ = feed(&recognizer, ratios: [0.1, 0.1])
        readings = feed(&recognizer, ratios: [0.1, 0.8, 0.1, 0.8, 0.1])
        XCTAssertTrue(readings.allSatisfy { $0.isPinched && $0.transition == .none })
    }

    func testNoisyLandmarksAroundAHeldPinchProduceASingleTransition() {
        var generator = SeededGenerator(seed: 42)
        var recognizer = PinchRecognizer(configuration: config)
        var transitions: [PinchTransition] = []
        for i in 0..<120 {
            let noisyRatio = 0.12 + Double.random(in: -0.08...0.08, using: &generator)
            let hand = TestHands.hand(at: Double(i) / 30, pinchRatio: noisyRatio, scale: Double.random(in: 0.8...1.2, using: &generator))
            let t = recognizer.update(with: hand).transition
            if t != .none { transitions.append(t) }
        }
        XCTAssertEqual(transitions, [.began])
    }

    func testNoisyLandmarksAroundAnOpenHandNeverPinch() {
        var generator = SeededGenerator(seed: 7)
        var recognizer = PinchRecognizer(configuration: config)
        for i in 0..<120 {
            let noisyRatio = 0.6 + Double.random(in: -0.2...0.2, using: &generator)
            let reading = recognizer.update(with: TestHands.hand(at: Double(i) / 30, pinchRatio: noisyRatio))
            XCTAssertFalse(reading.isPinched)
        }
    }

    func testAspectRatioIsCorrected() {
        // 16:9 image: a horizontal normalized distance is 16/9 times longer in pixels.
        let hand = HandState(
            timestamp: 0,
            landmarks: [
                .wrist: HandLandmark(Point2D(x: 0.5, y: 0.8)),
                .indexMCP: HandLandmark(Point2D(x: 0.5, y: 0.6)),
                .indexTip: HandLandmark(Point2D(x: 0.5, y: 0.4)),
                .thumbTip: HandLandmark(Point2D(x: 0.5 + 0.1 * 9 / 16, y: 0.4)),
            ],
            imageAspectRatio: 16.0 / 9.0
        )
        XCTAssertEqual(PinchRecognizer.pinchRatio(for: hand) ?? -1, 0.5, accuracy: 1e-9)
    }

    func testBriefOcclusionKeepsPinchButLongOcclusionReleases() {
        var recognizer = PinchRecognizer(configuration: config)
        _ = feed(&recognizer, ratios: [0.1, 0.1])
        for i in 0..<3 {
            let reading = recognizer.update(with: TestHands.hand(at: 1 + Double(i) / 30, pinchRatio: 0.1, omit: [.thumbTip]))
            XCTAssertTrue(reading.isPinched)
            XCTAssertNil(reading.ratio)
        }
        let reading = recognizer.update(with: TestHands.hand(at: 2, pinchRatio: 0.1, omit: [.thumbTip]))
        XCTAssertEqual(reading.transition, .ended)
        XCTAssertFalse(reading.isPinched)
    }

    func testLowConfidenceLandmarksAreNotMeasured() {
        var recognizer = PinchRecognizer(configuration: config)
        for i in 0..<5 {
            let reading = recognizer.update(with: TestHands.hand(at: Double(i) / 30, pinchRatio: 0.1, confidence: 0.1))
            XCTAssertNil(reading.ratio)
            XCTAssertFalse(reading.isPinched)
        }
    }

    func testDegenerateHandSizeIsNotMeasured() {
        let tiny = TestHands.hand(at: 0, pinchRatio: 0.1, scale: 0.05)
        XCTAssertNil(HandScale.referenceLength(of: tiny))
        XCTAssertNil(PinchRecognizer.pinchRatio(for: tiny))
    }

    func testInvalidConfigurationIsSanitized() {
        let bad = PinchConfiguration(startRatio: 0.4, releaseRatio: 0.3, startConfirmationFrames: 0, releaseConfirmationFrames: -1).sanitized
        XCTAssertGreaterThan(bad.releaseRatio, bad.startRatio)
        XCTAssertEqual(bad.startConfirmationFrames, 1)
        XCTAssertEqual(bad.releaseConfirmationFrames, 1)
    }
}
