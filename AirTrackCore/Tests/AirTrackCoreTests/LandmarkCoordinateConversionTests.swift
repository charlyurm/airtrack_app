import XCTest
@testable import AirTrackCore

final class LandmarkCoordinateConversionTests: XCTestCase {
    private typealias Raw = LandmarkCoordinateConversion.BottomLeftLandmark

    private func convert(_ points: [HandJoint: Raw], aspect: Double = 16.0 / 9.0) -> HandState {
        LandmarkCoordinateConversion.handState(fromBottomLeftOrigin: points, timestamp: 12.5, imageAspectRatio: aspect)
    }

    func testYAxisIsFlippedToTopLeftOrigin() {
        let state = convert([.indexTip: Raw(x: 0.25, y: 0.75, confidence: 0.9)])
        XCTAssertPointEqual(state.position(of: .indexTip), Point2D(x: 0.25, y: 0.25))
    }

    func testCornersMapToTheExpectedCorners() {
        let state = convert([
            .wrist: Raw(x: 0, y: 0, confidence: 1),    // bottom-left in provider space
            .indexTip: Raw(x: 1, y: 1, confidence: 1), // top-right in provider space
        ])
        XCTAssertPointEqual(state.position(of: .wrist), Point2D(x: 0, y: 1))
        XCTAssertPointEqual(state.position(of: .indexTip), Point2D(x: 1, y: 0))
    }

    func testXIsNeverMirrored() {
        let state = convert([.thumbTip: Raw(x: 0.1, y: 0.5, confidence: 1)])
        XCTAssertEqual(state.position(of: .thumbTip)?.x, 0.1)
    }

    func testConfidenceTimestampAndAspectArePreserved() {
        let state = convert([.indexMCP: Raw(x: 0.5, y: 0.5, confidence: 0.42)], aspect: 4.0 / 3.0)
        XCTAssertEqual(state.landmarks[.indexMCP]?.confidence, 0.42)
        XCTAssertEqual(state.timestamp, 12.5)
        XCTAssertEqual(state.imageAspectRatio, 4.0 / 3.0)
    }

    func testUndetectedAndInvalidJointsAreDropped() {
        let state = convert([
            .indexTip: Raw(x: 0.5, y: 0.5, confidence: 0.8),
            .ringTip: Raw(x: 0, y: 0, confidence: 0),
            .pinkyTip: Raw(x: .nan, y: 0.5, confidence: 0.9),
            .middleTip: Raw(x: 0.5, y: .infinity, confidence: 0.9),
        ])
        XCTAssertEqual(Set(state.landmarks.keys), [.indexTip])
        XCTAssertTrue(state.isTracked)
    }

    func testNoValidJointsMeansNotTracked() {
        XCTAssertFalse(convert([:]).isTracked)
        XCTAssertFalse(convert([.wrist: Raw(x: 0.5, y: 0.5, confidence: 0)]).isTracked)
    }

    func testConvertedHandFeedsThePinchRecognizer() {
        // Same geometry as TestHands, expressed in bottom-left coordinates: ratio 0.1 → pinched.
        let topLeft = TestHands.hand(at: 0, pinchRatio: 0.1)
        var raw: [HandJoint: Raw] = [:]
        for (joint, landmark) in topLeft.landmarks {
            raw[joint] = Raw(x: landmark.position.x, y: 1 - landmark.position.y, confidence: landmark.confidence)
        }
        let converted = LandmarkCoordinateConversion.handState(fromBottomLeftOrigin: raw, timestamp: 0, imageAspectRatio: 1)
        XCTAssertEqual(PinchRecognizer.pinchRatio(for: converted) ?? -1, 0.1, accuracy: 1e-9)
    }
}
