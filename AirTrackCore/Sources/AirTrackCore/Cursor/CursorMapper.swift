import Foundation

/// Camera-normalized index position → normalized display position.
///
/// Two steps, so a dead zone can sit between them (see CursorController):
/// 1. `normalizedInActiveArea`: mirror, then position inside the active area
///    (0…1 inside, beyond 0…1 outside; not clamped).
/// 2. `applyingSensitivity`: scale around the area center by `sensitivity`, then clamp to 0…1.
/// `map` = both steps. Scaling around the center after normalizing is exactly equivalent to
/// shrinking the active area by 1/sensitivity (`effectiveArea`).
///
/// Mirroring: HandState is the raw camera image. The camera faces the user, so the user's
/// physical LEFT is the image's RIGHT. `mirrorHorizontally` (default on) is the ONE place
/// that turns image space into the user's point of view for the cursor.
/// The active area lives in that mirrored space (what the user sees in the mirrored preview),
/// origin top-left, y down.
public struct CursorMapper: Equatable, Sendable {
    /// Hand travel inside 15 %…85 % of the image covers the whole screen. Initial, tunable.
    public static let defaultActiveArea = Rect2D(x: 0.15, y: 0.15, width: 0.7, height: 0.7)
    public static let sensitivityRange: ClosedRange<Double> = 0.5...3.0

    public var mirrorHorizontally: Bool
    public var activeArea: Rect2D
    /// 1 = the active area maps exactly onto the screen. >1 = less hand travel per screen.
    public var sensitivity: Double

    public init(mirrorHorizontally: Bool = true, activeArea: Rect2D = CursorMapper.defaultActiveArea, sensitivity: Double = 1.0) {
        self.mirrorHorizontally = mirrorHorizontally
        self.activeArea = activeArea
        self.sensitivity = sensitivity
    }

    public func mirrored(_ p: Point2D) -> Point2D {
        mirrorHorizontally ? Point2D(x: 1 - p.x, y: p.y) : p
    }

    /// Active area used for mapping (falls back to the default if the configured one is invalid).
    public var validActiveArea: Rect2D {
        activeArea.isValid ? activeArea : Self.defaultActiveArea
    }

    public var effectiveSensitivity: Double {
        guard sensitivity.isFinite else { return 1 }
        return min(max(sensitivity, Self.sensitivityRange.lowerBound), Self.sensitivityRange.upperBound)
    }

    /// Region of the (mirrored) camera image that spans the full screen at this sensitivity.
    public var effectiveArea: Rect2D {
        validActiveArea.scaled(by: 1 / effectiveSensitivity)
    }

    /// Step 1. nil for non-finite input so garbage never reaches the cursor.
    public func normalizedInActiveArea(_ cameraPoint: Point2D) -> Point2D? {
        guard cameraPoint.isFinite else { return nil }
        return validActiveArea.normalizedPosition(of: mirrored(cameraPoint))
    }

    /// Step 2. Always within 0…1.
    public func applyingSensitivity(_ normalized: Point2D) -> Point2D {
        let s = effectiveSensitivity
        let scaled = Point2D(x: 0.5 + (normalized.x - 0.5) * s, y: 0.5 + (normalized.y - 0.5) * s)
        return Rect2D.unit.clamp(scaled)
    }

    /// Both steps. Returns nil for non-finite input.
    public func map(_ cameraPoint: Point2D) -> Point2D? {
        normalizedInActiveArea(cameraPoint).map(applyingSensitivity)
    }
}
