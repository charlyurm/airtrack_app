import XCTest
@testable import AirTrackCore

/// Landmark identity: every joint must come out of the conversion as the same anatomical joint
/// it went in as, and every finger chain must follow its own finger.
final class HandJointIdentityTests: XCTestCase {
    private typealias Raw = LandmarkCoordinateConversion.BottomLeftLandmark

    /// Synthetic provider output (bottom-left origin, y up): open hand, fingers pointing up,
    /// each finger on its own vertical line so any identity swap moves a joint sideways.
    private static let fingerX: [Finger: Double] = [.thumb: 0.15, .index: 0.35, .middle: 0.5, .ring: 0.65, .pinky: 0.8]
    private static let segmentY: [Double] = [0.4, 0.5, 0.6, 0.7] // MCP/CMC → tip, going UP

    private func providerHand() -> [HandJoint: Raw] {
        var raw: [HandJoint: Raw] = [.wrist: Raw(x: 0.5, y: 0.1, confidence: 0.9)]
        for finger in Finger.allCases {
            let chain = HandSkeleton.chain(for: finger).dropFirst() // skip wrist
            for (joint, y) in zip(chain, Self.segmentY) {
                raw[joint] = Raw(x: Self.fingerX[finger]!, y: y, confidence: 0.9)
            }
        }
        return raw
    }

    private func converted() -> HandState {
        LandmarkCoordinateConversion.handState(fromBottomLeftOrigin: providerHand(), timestamp: 0, imageAspectRatio: 16.0 / 9.0)
    }

    // MARK: Skeleton definition

    func testThereAreExactly21DistinctJoints() {
        XCTAssertEqual(HandJoint.allCases.count, 21)
        XCTAssertEqual(Set(HandJoint.allCases.map(\.rawValue)).count, 21)
    }

    func testEveryChainStartsAtTheWristAndEndsAtItsOwnTip() {
        let expectedTips: [Finger: HandJoint] = [.thumb: .thumbTip, .index: .indexTip, .middle: .middleTip, .ring: .ringTip, .pinky: .pinkyTip]
        for finger in Finger.allCases {
            let chain = HandSkeleton.chain(for: finger)
            XCTAssertEqual(chain.count, 5, "\(finger)")
            XCTAssertEqual(chain.first, .wrist, "\(finger)")
            XCTAssertEqual(chain.last, expectedTips[finger], "\(finger)")
            XCTAssertEqual(HandSkeleton.tip(of: finger), expectedTips[finger])
        }
    }

    func testEveryNonWristJointBelongsToExactlyOneFinger() {
        for joint in HandJoint.allCases where joint != .wrist {
            let owners = Finger.allCases.filter { HandSkeleton.chain(for: $0).contains(joint) }
            XCTAssertEqual(owners.count, 1, "\(joint) belongs to \(owners)")
            XCTAssertEqual(HandSkeleton.finger(of: joint), owners.first)
        }
        XCTAssertNil(HandSkeleton.finger(of: .wrist))
    }

    // MARK: Identity through conversion

    func testFingertipsKeepTheirIdentity() {
        let raw: [HandJoint: Raw] = [
            .indexTip: Raw(x: 0.30, y: 0.20, confidence: 0.9),
            .middleTip: Raw(x: 0.50, y: 0.20, confidence: 0.9),
            .ringTip: Raw(x: 0.70, y: 0.20, confidence: 0.9),
            .pinkyTip: Raw(x: 0.90, y: 0.20, confidence: 0.9),
        ]
        let hand = LandmarkCoordinateConversion.handState(fromBottomLeftOrigin: raw, timestamp: 0, imageAspectRatio: 1)
        XCTAssertPointEqual(hand.position(of: .indexTip), Point2D(x: 0.30, y: 0.80))
        XCTAssertPointEqual(hand.position(of: .middleTip), Point2D(x: 0.50, y: 0.80))
        XCTAssertPointEqual(hand.position(of: .ringTip), Point2D(x: 0.70, y: 0.80))
        XCTAssertPointEqual(hand.position(of: .pinkyTip), Point2D(x: 0.90, y: 0.80))
    }

    func testEveryOneOf21JointsKeepsItsIdentity() {
        // Give each joint a unique position; any swap puts some joint at another joint's spot.
        var raw: [HandJoint: Raw] = [:]
        for (i, joint) in HandJoint.allCases.enumerated() {
            raw[joint] = Raw(x: 0.02 + Double(i) * 0.045, y: 0.95 - Double(i) * 0.04, confidence: 0.9)
        }
        let hand = LandmarkCoordinateConversion.handState(fromBottomLeftOrigin: raw, timestamp: 0, imageAspectRatio: 1)
        XCTAssertEqual(hand.landmarks.count, 21)
        for (i, joint) in HandJoint.allCases.enumerated() {
            XCTAssertPointEqual(hand.position(of: joint), Point2D(x: 0.02 + Double(i) * 0.045, y: 0.05 + Double(i) * 0.04))
        }
    }

    // MARK: Finger chains follow their own finger

    private func assertChainFollowsItsFinger(_ finger: Finger, file: StaticString = #filePath, line: UInt = #line) {
        let hand = converted()
        let chain = HandSkeleton.chain(for: finger).dropFirst()
        let expectedX = Self.fingerX[finger]!
        var previousY = Double.infinity
        for joint in chain {
            guard let p = hand.position(of: joint) else {
                XCTFail("\(joint) missing", file: file, line: line)
                return
            }
            XCTAssertEqual(p.x, expectedX, accuracy: 1e-9, "\(joint) drifted to another finger", file: file, line: line)
            XCTAssertLessThan(p.y, previousY, "\(joint): chain must run toward the top of the image", file: file, line: line)
            previousY = p.y
        }
    }

    func testIndexChainFollowsTheIndexFinger() { assertChainFollowsItsFinger(.index) }
    func testMiddleChainFollowsTheMiddleFinger() { assertChainFollowsItsFinger(.middle) }
    func testRingChainFollowsTheRingFinger() { assertChainFollowsItsFinger(.ring) }
    func testPinkyChainFollowsThePinky() { assertChainFollowsItsFinger(.pinky) }
    func testThumbChainFollowsTheThumb() { assertChainFollowsItsFinger(.thumb) }

    func testIndexTipIsNotTheMiddleTip() {
        let hand = converted()
        let index = hand.position(of: .indexTip)!
        let middle = hand.position(of: .middleTip)!
        XCTAssertEqual(index.x, 0.35, accuracy: 1e-9)
        XCTAssertEqual(middle.x, 0.5, accuracy: 1e-9)
        XCTAssertNotEqual(index, middle)
    }
}
