import Foundation

/// Hardware-independent pointer commands produced by the gesture layer.
///
/// Positions are normalized DISPLAY coordinates: 0...1, origin top-left,
/// y down. The macOS layer converts them with `ScreenMapper` and posts
/// one CGEvent per action. `clickCount` maps to kCGMouseEventClickState.
public enum InteractionAction: Equatable, Sendable {
    case moveCursor(to: Point2D)
    case mouseDown(at: Point2D, clickCount: Int)
    case mouseDrag(to: Point2D)
    case mouseUp(at: Point2D, clickCount: Int)
}
