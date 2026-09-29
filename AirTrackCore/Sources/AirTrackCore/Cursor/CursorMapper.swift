import Foundation

/// Camera-normalized index position → normalized display position.
///
/// Pipeline: mirror → active area (shrunk by sensitivity) → 0...1 → clamp.
/// The active area lives in MIRRORED camera space (what the user sees in a
/// selfie-style preview), origin top-left, y down.
public struct CursorMapper: Equatable, Sendable {
    public static let defaultActiveArea = Rect2D(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
    public static let sensitivityRange: ClosedRange<Double> = 0.5...3.0

    public var mirrorHorizontally: Bool
    public var activeArea: Rect2D
    /// 1 = use the active area as is. >1 shrinks it (less hand travel per screen).
    public var sensitivity: Double

    public init(mirrorHorizontally: Bool = true, activeArea: Rect2D = CursorMapper.defaultActiveArea, sensitivity: Double = 1.0) {
        self.mirrorHorizontally = mirrorHorizontally
        self.activeArea = activeArea
        self.sensitivity = sensitivity
    }

    public func mirrored(_ p: Point2D) -> Point2D {
        mirrorHorizontally ? Point2D(x: 1 - p.x, y: p.y) : p
    }

    public var effectiveArea: Rect2D {
        let area = activeArea.isValid ? activeArea : Self.defaultActiveArea
        let s = sensitivity.isFinite
            ? min(max(sensitivity, Self.sensitivityRange.lowerBound), Self.sensitivityRange.upperBound)
            : 1.0
        return area.scaled(by: 1 / s)
    }

    /// Returns nil for non-finite input so garbage never reaches the cursor.
    public func map(_ cameraPoint: Point2D) -> Point2D? {
        guard cameraPoint.isFinite else { return nil }
        let normalized = effectiveArea.normalizedPosition(of: mirrored(cameraPoint))
        return Rect2D.unit.clamp(normalized)
    }
}
