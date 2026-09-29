import AirTrackCore
import CoreGraphics

/// The only place AirTrack talks to the system cursor. PHASE 2: MOVE ONLY — this type
/// deliberately has no mouseDown / mouseUp / click / drag / scroll.
///
/// Coordinates: CoreGraphics global display space — origin at the top-left of the main
/// display, y down, in points (logical, Retina-independent). Same convention as
/// AirTrackCore's ScreenMapper, so no conversion is needed.
/// Thread-safe (no state; CoreGraphics event and display calls work from any thread).
final class MacOSEventController: Sendable {
    /// Main display (the one with the menu bar). Multi-display targeting is not in PHASE 2.
    func mainDisplayBounds() -> Rect2D {
        let bounds = CGDisplayBounds(CGMainDisplayID())
        return Rect2D(
            x: Double(bounds.origin.x),
            y: Double(bounds.origin.y),
            width: Double(bounds.size.width),
            height: Double(bounds.size.height)
        )
    }

    /// Where the system cursor is right now (same global space).
    func currentCursorLocation() -> Point2D? {
        guard let location = CGEvent(source: nil)?.location else { return nil }
        return Point2D(x: Double(location.x), y: Double(location.y))
    }

    /// Posts a mouse-moved event, so apps see normal hover/move events. Needs the Accessibility
    /// permission; without it macOS silently drops the event (the caller checks first).
    func moveCursor(to point: Point2D) {
        guard point.isFinite else { return }
        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: CGPoint(x: point.x, y: point.y),
            mouseButton: .left // required parameter; ignored for .mouseMoved
        )
        event?.post(tap: .cghidEventTap)
    }
}
