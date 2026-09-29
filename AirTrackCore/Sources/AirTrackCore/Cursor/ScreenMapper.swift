import Foundation

/// Normalized display position → macOS global display coordinates.
///
/// Global coordinates (what CGEvent / CGDisplayBounds use): points, not pixels
/// (Retina scaling is already applied by the system), origin at the top-left of
/// the primary display, y grows DOWN. Secondary displays can have negative origins.
///
/// AppKit (NSScreen.frame) uses origin bottom-left, y UP; convert with
/// `globalFrame(fromAppKitFrame:primaryDisplayHeight:)`.
public enum ScreenMapper {
    /// Maps onto a single display. The last addressable point is max - 1 so the
    /// cursor never lands on the neighbouring display.
    public static func map(_ normalized: Point2D, to display: Rect2D) -> Point2D? {
        guard display.isValid, normalized.isFinite else { return nil }
        let p = display.point(atNormalized: Rect2D.unit.clamp(normalized))
        let maxX = max(display.minX, display.maxX - 1)
        let maxY = max(display.minY, display.maxY - 1)
        return Point2D(x: min(p.x, maxX), y: min(p.y, maxY))
    }

    public static func globalFrame(fromAppKitFrame frame: Rect2D, primaryDisplayHeight: Double) -> Rect2D {
        Rect2D(x: frame.minX, y: primaryDisplayHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    public static func display(containing point: Point2D, in displays: [Rect2D]) -> Rect2D? {
        displays.first { $0.contains(point) }
    }
}
