import Foundation

/// Platform-independent 2D point. AirTrackCore deliberately avoids CGPoint so it
/// builds and tests identically on macOS and Linux.
public struct Point2D: Equatable, Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Point2D(x: 0, y: 0)

    public var isFinite: Bool { x.isFinite && y.isFinite }

    public var length: Double { (x * x + y * y).squareRoot() }

    public func distance(to other: Point2D) -> Double { (self - other).length }

    public static func + (lhs: Point2D, rhs: Point2D) -> Point2D {
        Point2D(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    public static func - (lhs: Point2D, rhs: Point2D) -> Point2D {
        Point2D(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    public static func * (lhs: Point2D, rhs: Double) -> Point2D {
        Point2D(x: lhs.x * rhs, y: lhs.y * rhs)
    }
}
