import Foundation

/// PHASE 3A: hand poses the interaction engine understands. `unknown` is a valid, frequent
/// answer: an uncertain pose never becomes a gesture.
public enum HandPose: String, Equatable, Sendable, CaseIterable {
    /// ☝️ index extended, middle/ring/little bent.
    case pointing
    /// ☝️🖕 index + middle extended, ring + little bent. The fingers need not touch.
    case twoFinger
    /// 🖐️ fingers extended, thumb not folded. Tolerates one uncertain finger.
    case openHand
    /// Four fingers extended with the thumb clearly folded (conservative).
    case fourFinger
    /// 🤏 thumb tip close to index tip (relative to hand size).
    case pinch
    case unknown
}

/// Thresholds in hand-scale units / frames. UNCALIBRATED (REQUIRES MACOS).
public struct PoseConfiguration: Equatable, Sendable {
    /// Thumb–index distance / scale to enter PINCH, and to leave it (hysteresis).
    public var pinchEnterDistance: Double = 0.25
    public var pinchExitDistance: Double = 0.35
    /// Thumb touching the middle tip (future right click): two-finger is then ambiguous.
    public var thumbMiddleContactDistance: Double = 0.25
    /// Consecutive frames a new raw pose must persist before it becomes the stable pose.
    public var stableFrames: Int = 2

    public init() {}
}

/// Features → pose, with hysteresis. One noisy frame never changes the stable pose.
public struct PoseClassifier: Sendable {
    public var configuration: PoseConfiguration
    public private(set) var stablePose: HandPose = .unknown
    /// Pose of the latest frame before hysteresis (diagnostics, continuation checks).
    public private(set) var rawPose: HandPose = .unknown
    private var pendingPose: HandPose = .unknown
    private var pendingFrames = 0

    public init(configuration: PoseConfiguration = PoseConfiguration()) {
        self.configuration = configuration
    }

    /// Pure classification of one frame. `current` enables the pinch hysteresis band.
    public static func classify(_ f: HandFeatures, current: HandPose = .unknown, configuration c: PoseConfiguration = PoseConfiguration()) -> HandPose {
        let thumb = f.state(of: .thumb)
        let index = f.state(of: .index)
        let middle = f.state(of: .middle)
        let ring = f.state(of: .ring)
        let pinky = f.state(of: .pinky)

        // A thumb folded against the palm (fist) can lie next to a curled index: not a pinch.
        if let d = f.thumbIndexDistance, thumb != .bent {
            let limit = current == .pinch ? c.pinchExitDistance : c.pinchEnterDistance
            if d <= limit { return .pinch }
        }
        if index == .extended, middle == .bent, ring != .extended, pinky != .extended {
            return .pointing
        }
        if index == .extended, middle == .extended, ring == .bent, pinky == .bent {
            // Thumb resting on the middle tip is the future right-click relation: ambiguous.
            if let d = f.thumbMiddleDistance, d <= c.thumbMiddleContactDistance { return .unknown }
            return .twoFinger
        }
        let four: [FingerState] = [index, middle, ring, pinky]
        let extendedCount = four.filter { $0 == .extended }.count
        if four.allSatisfy({ $0 == .extended }), thumb == .bent {
            return .fourFinger
        }
        if index == .extended, middle == .extended, extendedCount >= 3, !four.contains(.bent), thumb != .bent {
            return .openHand
        }
        return .unknown
    }

    /// Feeds one frame. nil features (no measurable hand) → unknown immediately: without
    /// landmarks there is nothing to keep a pose alive.
    @discardableResult
    public mutating func update(_ features: HandFeatures?) -> HandPose {
        guard let features else {
            reset()
            return stablePose
        }
        let raw = Self.classify(features, current: stablePose, configuration: configuration)
        rawPose = raw
        if raw == stablePose {
            pendingFrames = 0
            pendingPose = raw
            return stablePose
        }
        if raw == pendingPose {
            pendingFrames += 1
        } else {
            pendingPose = raw
            pendingFrames = 1
        }
        if pendingFrames >= max(1, configuration.stableFrames) {
            stablePose = raw
            pendingFrames = 0
        }
        return stablePose
    }

    public mutating func reset() {
        stablePose = .unknown
        rawPose = .unknown
        pendingPose = .unknown
        pendingFrames = 0
    }
}
