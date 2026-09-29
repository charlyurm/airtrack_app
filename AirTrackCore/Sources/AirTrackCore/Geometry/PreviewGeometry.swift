import Foundation

/// HandState coordinates → on-screen preview coordinates.
///
/// View space: origin TOP-left, y down, in points (SwiftUI's convention on every platform).
/// The preview shows the camera image scaled to fit and centered (letterboxed), which is what
/// AVLayerVideoGravity.resizeAspect does. Mirroring is a display choice; HandState is never
/// mirrored.
public enum PreviewGeometry {
    /// Rect the image occupies inside the view. nil for degenerate sizes.
    public static func aspectFitRect(imageAspectRatio: Double, viewWidth: Double, viewHeight: Double) -> Rect2D? {
        guard imageAspectRatio.isFinite, imageAspectRatio > 0,
              viewWidth.isFinite, viewHeight.isFinite, viewWidth > 0, viewHeight > 0 else { return nil }
        if viewWidth / viewHeight > imageAspectRatio {
            // View is wider than the image: bars left and right.
            let width = viewHeight * imageAspectRatio
            return Rect2D(x: (viewWidth - width) / 2, y: 0, width: width, height: viewHeight)
        } else {
            // View is taller than the image: bars top and bottom.
            let height = viewWidth / imageAspectRatio
            return Rect2D(x: 0, y: (viewHeight - height) / 2, width: viewWidth, height: height)
        }
    }

    /// A HandState point (0…1, top-left, unmirrored) as a view point (top-left, y down).
    /// It is an affine map, so relative geometry (hand shape, size, distances) is preserved.
    public static func viewPoint(
        for point: Point2D,
        imageAspectRatio: Double,
        viewWidth: Double,
        viewHeight: Double,
        mirrored: Bool
    ) -> Point2D? {
        guard point.isFinite,
              let rect = aspectFitRect(imageAspectRatio: imageAspectRatio, viewWidth: viewWidth, viewHeight: viewHeight)
        else { return nil }
        let x = mirrored ? 1 - point.x : point.x
        return rect.point(atNormalized: Point2D(x: x, y: point.y))
    }
}
