import Foundation

/// Two-corner active-area calibration: the user points at the top-left and the
/// bottom-right of the region they want to map to the whole screen.
///
/// Samples must be in MIRRORED camera space (`CursorMapper.mirrored(_:)`), i.e. the
/// same space as `CursorMapper.activeArea`.
public enum ActiveAreaCalibration {
    public static let minimumSize = 0.1

    /// Returns nil when the samples are invalid or describe an area too small to be usable.
    public static func activeArea(topLeft: Point2D, bottomRight: Point2D, minimumSize: Double = ActiveAreaCalibration.minimumSize) -> Rect2D? {
        guard topLeft.isFinite, bottomRight.isFinite,
              let area = Rect2D(corner: topLeft, corner: bottomRight).intersection(with: .unit),
              area.width >= minimumSize, area.height >= minimumSize else { return nil }
        return area
    }
}
