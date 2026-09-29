import Foundation

/// Minimum landmark set required by AirTrack. Provider-agnostic: the macOS
/// Vision adapter maps its own joint names onto these.
public enum HandJoint: String, CaseIterable, Codable, Sendable {
    case wrist
    case thumbTip
    case indexMCP
    case indexPIP
    case indexDIP
    case indexTip
    case middleTip
    case ringTip
    case pinkyTip
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
