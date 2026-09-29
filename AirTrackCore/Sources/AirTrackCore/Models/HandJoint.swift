import Foundation

/// The 21 hand landmarks, named anatomically. Provider-agnostic: the macOS Vision adapter maps
/// each Vision joint identifier onto one of these explicitly (never by array position).
/// Vision calls the fifth finger "little"; AirTrack calls it "pinky".
public enum HandJoint: String, CaseIterable, Codable, Sendable {
    case wrist
    case thumbCMC, thumbMP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case pinkyMCP, pinkyPIP, pinkyDIP, pinkyTip
}

public enum Finger: String, CaseIterable, Codable, Sendable {
    case thumb, index, middle, ring, pinky
}

/// Anatomical structure of the hand, used to draw and validate finger chains.
public enum HandSkeleton {
    /// Joints of one finger from the wrist outwards (proximal → distal).
    public static func chain(for finger: Finger) -> [HandJoint] {
        switch finger {
        case .thumb: [.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip]
        case .index: [.wrist, .indexMCP, .indexPIP, .indexDIP, .indexTip]
        case .middle: [.wrist, .middleMCP, .middlePIP, .middleDIP, .middleTip]
        case .ring: [.wrist, .ringMCP, .ringPIP, .ringDIP, .ringTip]
        case .pinky: [.wrist, .pinkyMCP, .pinkyPIP, .pinkyDIP, .pinkyTip]
        }
    }

    public static func tip(of finger: Finger) -> HandJoint {
        chain(for: finger)[4]
    }

    /// The finger a joint belongs to; nil for the wrist, which is shared by all fingers.
    public static func finger(of joint: HandJoint) -> Finger? {
        guard joint != .wrist else { return nil }
        return Finger.allCases.first { chain(for: $0).contains(joint) }
    }
}

public enum HandChirality: String, Codable, Sendable {
    case left, right, unknown
}

public struct HandLandmark: Equatable, Sendable {
    public var position: Point2D
    /// 0...1 as reported by the tracking provider.
    public var confidence: Double

    public init(_ position: Point2D, confidence: Double = 1) {
        self.position = position
        self.confidence = confidence
    }
}
