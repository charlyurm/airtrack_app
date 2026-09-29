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

extension TestHands {
    /// Open hand, fingers pointing UP, in HandState space (top-left origin, y down), all 21
    /// joints. At scale 1 the hand spans ~0.26 of the image height; wrist→indexMCP ≈ 0.13.
    static let openHandOffsets: [HandJoint: Point2D] = [
        .wrist: Point2D(x: 0, y: 0.15),
        .thumbCMC: Point2D(x: -0.05, y: 0.10), .thumbMP: Point2D(x: -0.08, y: 0.06),
        .thumbIP: Point2D(x: -0.10, y: 0.03), .thumbTip: Point2D(x: -0.12, y: 0.00),
        .indexMCP: Point2D(x: -0.03, y: 0.02), .indexPIP: Point2D(x: -0.035, y: -0.03),
        .indexDIP: Point2D(x: -0.04, y: -0.06), .indexTip: Point2D(x: -0.045, y: -0.09),
        .middleMCP: Point2D(x: 0.0, y: 0.015), .middlePIP: Point2D(x: 0.0, y: -0.04),
        .middleDIP: Point2D(x: 0.0, y: -0.075), .middleTip: Point2D(x: 0.0, y: -0.11),
        .ringMCP: Point2D(x: 0.03, y: 0.02), .ringPIP: Point2D(x: 0.035, y: -0.03),
        .ringDIP: Point2D(x: 0.04, y: -0.06), .ringTip: Point2D(x: 0.045, y: -0.085),
        .pinkyMCP: Point2D(x: 0.055, y: 0.035), .pinkyPIP: Point2D(x: 0.065, y: -0.005),
        .pinkyDIP: Point2D(x: 0.072, y: -0.03), .pinkyTip: Point2D(x: 0.08, y: -0.05),
    ]

    static func openHand(
        at time: TimeInterval = 0,
        center: Point2D = Point2D(x: 0.5, y: 0.5),
        scale: Double = 1,
        jointConfidence: Double = 0.9,
        handConfidence: Double = 0.95,
        chirality: HandChirality = .unknown,
        omit: Set<HandJoint> = []
    ) -> HandState {
        var landmarks: [HandJoint: HandLandmark] = [:]
        for (joint, offset) in openHandOffsets where !omit.contains(joint) {
            landmarks[joint] = HandLandmark(center + offset * scale, confidence: jointConfidence)
        }
        return HandState(timestamp: time, landmarks: landmarks, imageAspectRatio: 1, chirality: chirality, confidence: handConfidence)
    }
}

extension TestHands {
    /// Full valid open hand whose index tip sits exactly at `indexTip` (raw camera space).
    static func pointing(at indexTip: Point2D, time: TimeInterval = 0, indexConfidence: Double = 0.9) -> HandState {
        var hand = openHand(at: time, center: indexTip - openHandOffsets[.indexTip]!)
        hand.landmarks[.indexTip] = HandLandmark(indexTip, confidence: indexConfidence)
        return hand
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
