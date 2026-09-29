import Foundation

/// Axis-aligned rectangle. `x`/`y` is the minimum corner; the meaning of "up"
/// depends on the coordinate space the rect lives in (documented at each use).
public struct Rect2D: Equatable, Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Rectangle spanning two arbitrary opposite corners.
    public init(corner a: Point2D, corner b: Point2D) {
        let minX = min(a.x, b.x)
        let minY = min(a.y, b.y)
        self.init(x: minX, y: minY, width: max(a.x, b.x) - minX, height: max(a.y, b.y) - minY)
    }

    public static let unit = Rect2D(x: 0, y: 0, width: 1, height: 1)

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var center: Point2D { Point2D(x: x + width / 2, y: y + height / 2) }

    public var isValid: Bool {
        x.isFinite && y.isFinite && width.isFinite && height.isFinite && width > 0 && height > 0
    }

    /// Half-open containment: [min, max). Adjacent rects never both contain a shared edge.
    public func contains(_ p: Point2D) -> Bool {
        p.x >= minX && p.x < maxX && p.y >= minY && p.y < maxY
    }

    /// Closed clamp: [min, max].
    public func clamp(_ p: Point2D) -> Point2D {
        Point2D(x: min(max(p.x, minX), maxX), y: min(max(p.y, minY), maxY))
    }

    /// Position of `p` relative to this rect, where the rect spans 0...1 on both axes.
    public func normalizedPosition(of p: Point2D) -> Point2D {
        Point2D(x: (p.x - minX) / width, y: (p.y - minY) / height)
    }

    /// Inverse of `normalizedPosition(of:)`.
    public func point(atNormalized n: Point2D) -> Point2D {
        Point2D(x: minX + n.x * width, y: minY + n.y * height)
    }

    /// Scales width and height by `factor`, keeping the center fixed.
    public func scaled(by factor: Double) -> Rect2D {
        let c = center
        let w = width * factor
        let h = height * factor
        return Rect2D(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
    }

    public func intersection(with other: Rect2D) -> Rect2D? {
        let minX = max(self.minX, other.minX)
        let minY = max(self.minY, other.minY)
        let maxX = min(self.maxX, other.maxX)
        let maxY = min(self.maxY, other.maxY)
        guard maxX > minX, maxY > minY else { return nil }
        return Rect2D(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
