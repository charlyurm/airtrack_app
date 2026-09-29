import XCTest
@testable import AirTrackCore

enum TestHands {
    /// Synthetic hand in camera space (top-left origin, unmirrored).
    ///
    /// Reference segment wrist → indexMCP has length `0.2 * scale`, so the
    /// thumb–index distance of `pinchRatio * 0.2 * scale` yields exactly `pinchRatio`.
    static func hand(
        at time: TimeInterval,
        indexTip: Point2D = Point2D(x: 0.5, y: 0.5),
        pinchRatio: Double,
        scale: Double = 1,
        confidence: Double = 1,
        omit: Set<HandJoint> = []
    ) -> HandState {
        let reference = 0.2 * scale
        var joints: [HandJoint: Point2D] = [
            .indexTip: indexTip,
            .thumbTip: Point2D(x: indexTip.x + pinchRatio * reference, y: indexTip.y),
            .indexDIP: Point2D(x: indexTip.x, y: indexTip.y + 0.03 * scale),
            .indexPIP: Point2D(x: indexTip.x, y: indexTip.y + 0.06 * scale),
            .indexMCP: Point2D(x: indexTip.x, y: indexTip.y + 0.1 * scale),
            .wrist: Point2D(x: indexTip.x, y: indexTip.y + 0.1 * scale + reference),
            .middleTip: Point2D(x: indexTip.x - 0.03 * scale, y: indexTip.y),
            .ringTip: Point2D(x: indexTip.x - 0.06 * scale, y: indexTip.y + 0.01 * scale),
            .pinkyTip: Point2D(x: indexTip.x - 0.09 * scale, y: indexTip.y + 0.03 * scale),
        ]
        for joint in omit { joints[joint] = nil }
        return HandState(
            timestamp: time,
            landmarks: joints.mapValues { HandLandmark($0, confidence: confidence) }
        )
    }
}

/// Deterministic pseudo-random generator for reproducible "noisy landmark" tests.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

func XCTAssertPointEqual(_ a: Point2D?, _ b: Point2D, accuracy: Double = 1e-9, file: StaticString = #filePath, line: UInt = #line) {
    guard let a else {
        XCTFail("point is nil, expected \(b)", file: file, line: line)
        return
    }
    XCTAssertEqual(a.x, b.x, accuracy: accuracy, "x", file: file, line: line)
    XCTAssertEqual(a.y, b.y, accuracy: accuracy, "y", file: file, line: line)
}

func XCTAssertRectEqual(_ a: Rect2D?, _ b: Rect2D, accuracy: Double = 1e-9, file: StaticString = #filePath, line: UInt = #line) {
    guard let a else {
        XCTFail("rect is nil, expected \(b)", file: file, line: line)
        return
    }
    XCTAssertEqual(a.x, b.x, accuracy: accuracy, "x", file: file, line: line)
    XCTAssertEqual(a.y, b.y, accuracy: accuracy, "y", file: file, line: line)
    XCTAssertEqual(a.width, b.width, accuracy: accuracy, "width", file: file, line: line)
    XCTAssertEqual(a.height, b.height, accuracy: accuracy, "height", file: file, line: line)
}
