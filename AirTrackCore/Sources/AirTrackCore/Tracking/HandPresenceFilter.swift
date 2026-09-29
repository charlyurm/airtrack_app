import Foundation

public struct HandFilterConfiguration: Equatable, Sendable, Codable {
    /// Below this provider confidence the observation is not treated as a hand.
    public var minimumHandConfidence: Double
    /// Joints below this confidence are removed (never drawn, never used).
    public var minimumJointConfidence: Double
    /// Joints every accepted hand must have (what cursor and pinch need).
    public var requiredJoints: Set<HandJoint>
    /// Minimum number of confident joints out of 21. Partial or spurious detections have few.
    public var minimumValidJoints: Int
    /// Minimum wrist → indexMCP length, in image heights. Rejects tiny spurious detections.
    public var minimumHandSize: Double
    /// Joints this far outside the image (normalized units) are removed.
    public var boundsTolerance: Double
    /// Consecutive frames with a valid hand before tracking is reported. Rejects one-frame
    /// false positives. Losing tracking is always immediate.
    public var framesToAcquire: Int
    public var maximumHands: Int

    /// UNCALIBRATED starting values; they must be tuned with the real camera (REQUIRES MACOS).
    public init(
        minimumHandConfidence: Double = 0.3,
        minimumJointConfidence: Double = 0.3,
        requiredJoints: Set<HandJoint> = [.wrist, .thumbTip, .indexMCP, .indexTip],
        minimumValidJoints: Int = 10,
        minimumHandSize: Double = 0.02,
        boundsTolerance: Double = 0.05,
        framesToAcquire: Int = 2,
        maximumHands: Int = 2
    ) {
        self.minimumHandConfidence = minimumHandConfidence
        self.minimumJointConfidence = minimumJointConfidence
        self.requiredJoints = requiredJoints
        self.minimumValidJoints = minimumValidJoints
        self.minimumHandSize = minimumHandSize
        self.boundsTolerance = boundsTolerance
        self.framesToAcquire = framesToAcquire
        self.maximumHands = maximumHands
    }
}

public enum HandRejectionReason: Error, Equatable, Sendable {
    case lowHandConfidence
    case missingRequiredJoint(HandJoint)
    case tooFewJoints(Int)
    case handTooSmall
}

public enum HandValidation {
    /// Returns the hand without unusable joints, or why it cannot be trusted.
    public static func validate(_ hand: HandState, configuration: HandFilterConfiguration) -> Result<HandState, HandRejectionReason> {
        guard hand.confidence.isFinite, hand.confidence >= configuration.minimumHandConfidence else {
            return .failure(.lowHandConfidence)
        }

        let low = -configuration.boundsTolerance
        let high = 1 + configuration.boundsTolerance
        var cleaned = hand
        cleaned.landmarks = hand.landmarks.filter { _, landmark in
            landmark.confidence.isFinite
                && landmark.confidence >= configuration.minimumJointConfidence
                && landmark.position.isFinite
                && (low...high).contains(landmark.position.x)
                && (low...high).contains(landmark.position.y)
        }

        if let missing = HandJoint.allCases.first(where: { configuration.requiredJoints.contains($0) && cleaned.landmarks[$0] == nil }) {
            return .failure(.missingRequiredJoint(missing))
        }
        guard cleaned.landmarks.count >= configuration.minimumValidJoints else {
            return .failure(.tooFewJoints(cleaned.landmarks.count))
        }
        guard let size = cleaned.aspectCorrectedDistance(from: .wrist, to: .indexMCP),
              size >= configuration.minimumHandSize else {
            return .failure(.handTooSmall)
        }
        return .success(cleaned)
    }
}

/// Per-frame gate between the tracking provider and the rest of AirTrack.
///
/// - Only observations that pass `HandValidation` count as hands.
/// - Output is always built from the CURRENT frame only: a frame without valid hands yields
///   no hands immediately. Old landmarks are never carried forward.
/// - Tracking is reported after `framesToAcquire` consecutive frames with a valid hand.
/// - Hands come out in `HandOrdering` order, capped at `maximumHands`.
public struct HandPresenceFilter: Sendable {
    public var configuration: HandFilterConfiguration
    public private(set) var consecutiveFramesWithHand = 0
    /// Why candidates were rejected in the last frame (diagnostics).
    public private(set) var lastRejections: [HandRejectionReason] = []

    public init(configuration: HandFilterConfiguration = HandFilterConfiguration()) {
        self.configuration = configuration
    }

    public mutating func update(candidates: [HandState]) -> [HandState] {
        var valid: [HandState] = []
        var rejections: [HandRejectionReason] = []
        for candidate in candidates {
            switch HandValidation.validate(candidate, configuration: configuration) {
            case let .success(hand): valid.append(hand)
            case let .failure(reason): rejections.append(reason)
            }
        }
        lastRejections = rejections

        let hands = Array(HandOrdering.ordered(valid).prefix(max(0, configuration.maximumHands)))
        guard !hands.isEmpty else {
            consecutiveFramesWithHand = 0
            return []
        }
        consecutiveFramesWithHand += 1
        return consecutiveFramesWithHand >= max(1, configuration.framesToAcquire) ? hands : []
    }

    public mutating func reset() {
        consecutiveFramesWithHand = 0
        lastRejections = []
    }
}
