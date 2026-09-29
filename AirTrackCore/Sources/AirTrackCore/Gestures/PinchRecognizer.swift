import Foundation

public struct PinchConfiguration: Equatable, Sendable, Codable {
    /// Pinch starts when thumbTip–indexTip distance / hand reference length drops below this.
    public var startRatio: Double
    /// Pinch releases when the ratio rises above this (hysteresis band in between).
    public var releaseRatio: Double
    /// Consecutive frames required to confirm a start / release (rejects one-frame spikes).
    /// PROVISIONAL: 2 frames ≈ 33 ms at 30 fps, accepted to avoid false clicks. Revisit only
    /// with latency measured on real hardware (fewer frames, timestamps or prediction).
    public var startConfirmationFrames: Int
    public var releaseConfirmationFrames: Int
    /// Frames without a measurable ratio (e.g. occluded thumb) tolerated while pinched.
    public var maxUnmeasurableFrames: Int
    public var minimumConfidence: Double

    /// UNCALIBRATED starting values. 0.25 / 0.35 are ratios of hand size (see HandScale),
    /// chosen from typical hand proportions, not from measurements. They MUST be validated
    /// with the real camera and real hands (REQUIRES MACOS). Never replace them with an
    /// absolute image distance.
    public init(
        startRatio: Double = 0.25,
        releaseRatio: Double = 0.35,
        startConfirmationFrames: Int = 2,
        releaseConfirmationFrames: Int = 2,
        maxUnmeasurableFrames: Int = 3,
        minimumConfidence: Double = 0.3
    ) {
        self.startRatio = startRatio
        self.releaseRatio = releaseRatio
        self.startConfirmationFrames = startConfirmationFrames
        self.releaseConfirmationFrames = releaseConfirmationFrames
        self.maxUnmeasurableFrames = maxUnmeasurableFrames
        self.minimumConfidence = minimumConfidence
    }

    /// Guarantees start > 0, release > start and positive frame counts.
    public var sanitized: PinchConfiguration {
        var c = self
        if !(c.startRatio.isFinite && c.startRatio > 0) { c.startRatio = PinchConfiguration().startRatio }
        if !(c.releaseRatio.isFinite && c.releaseRatio > c.startRatio) { c.releaseRatio = c.startRatio * 1.4 }
        c.startConfirmationFrames = max(1, c.startConfirmationFrames)
        c.releaseConfirmationFrames = max(1, c.releaseConfirmationFrames)
        c.maxUnmeasurableFrames = max(0, c.maxUnmeasurableFrames)
        if !c.minimumConfidence.isFinite { c.minimumConfidence = 0 }
        return c
    }
}

public enum PinchTransition: Equatable, Sendable {
    case none
    case began
    case ended
}

public struct PinchReading: Equatable, Sendable {
    public var isPinched: Bool
    /// nil when the ratio could not be measured this frame.
    public var ratio: Double?
    public var transition: PinchTransition

    public init(isPinched: Bool, ratio: Double?, transition: PinchTransition) {
        self.isPinched = isPinched
        self.ratio = ratio
        self.transition = transition
    }
}

/// Scale-invariant thumb–index pinch detector with hysteresis and frame debouncing.
public struct PinchRecognizer: Sendable {
    public var configuration: PinchConfiguration
    public private(set) var isPinched = false
    private var pendingFrames = 0
    private var unmeasurableFrames = 0

    public init(configuration: PinchConfiguration = PinchConfiguration()) {
        self.configuration = configuration
    }

    public static func pinchRatio(for hand: HandState, minimumConfidence: Double = 0) -> Double? {
        HandScale.normalizedDistance(from: .thumbTip, to: .indexTip, in: hand, minimumConfidence: minimumConfidence)
    }

    public mutating func update(with hand: HandState) -> PinchReading {
        let config = configuration.sanitized

        guard let ratio = Self.pinchRatio(for: hand, minimumConfidence: config.minimumConfidence) else {
            pendingFrames = 0
            unmeasurableFrames += 1
            if isPinched && unmeasurableFrames > config.maxUnmeasurableFrames {
                reset()
                return PinchReading(isPinched: false, ratio: nil, transition: .ended)
            }
            return PinchReading(isPinched: isPinched, ratio: nil, transition: .none)
        }
        unmeasurableFrames = 0

        if isPinched {
            if ratio > config.releaseRatio {
                pendingFrames += 1
                if pendingFrames >= config.releaseConfirmationFrames {
                    isPinched = false
                    pendingFrames = 0
                    return PinchReading(isPinched: false, ratio: ratio, transition: .ended)
                }
            } else {
                pendingFrames = 0
            }
        } else {
            if ratio < config.startRatio {
                pendingFrames += 1
                if pendingFrames >= config.startConfirmationFrames {
                    isPinched = true
                    pendingFrames = 0
                    return PinchReading(isPinched: true, ratio: ratio, transition: .began)
                }
            } else {
                pendingFrames = 0
            }
        }
        return PinchReading(isPinched: isPinched, ratio: ratio, transition: .none)
    }

    public mutating func reset() {
        isPinched = false
        pendingFrames = 0
        unmeasurableFrames = 0
    }
}
