import AirTrackCore
import CoreGraphics

/// The only place AirTrack talks to the system cursor. PHASE 2: move. PHASE 3A-2: scroll.
/// PHASE 3B: primary-button click, mouseDown / dragged / mouseUp. It posts; it does not decide:
/// which button events are owed (and that every mouseDown gets its mouseUp) is tracked by the
/// pipeline's DragController ledger.
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

    /// Posts the scroll actions of the interaction engine. PHASE 3B button actions need
    /// positions and the button ledger, so the pipeline posts them through the primary-button
    /// methods below; the legacy Phase 0 mouse cases are never produced and are ignored.
    func post(_ actions: [InteractionAction], invertScroll: Bool) {
        for action in actions {
            switch action {
            case let .scroll(scroll):
                postScroll(scroll, inverted: invertScroll)
            case .moveCursor, .mouseDown, .mouseDrag, .mouseUp, .leftClick, .beginDrag, .endDrag:
                break
            }
        }
    }

    /// One left click at `point`: leftMouseDown + leftMouseUp with click state 1 (a single
    /// click; nothing here ever sends click state 2, so no double click is synthesized).
    func postLeftClick(at point: Point2D) {
        guard point.isFinite else { return }
        postMouse(.leftMouseDown, at: point)
        postMouse(.leftMouseUp, at: point)
    }

    /// Primary button down (drag start).
    func postLeftMouseDown(at point: Point2D) {
        postMouse(.leftMouseDown, at: point)
    }

    /// Movement with the primary button held. macOS delivers pointer motion with a button down
    /// as `leftMouseDragged` (a plain mouseMoved would not drag anything); it also moves the
    /// cursor, so during a drag this is the only cursor writer.
    func postLeftMouseDragged(to point: Point2D) {
        postMouse(.leftMouseDragged, at: point)
    }

    /// Primary button up (drag end, or the safety release).
    func postLeftMouseUp(at point: Point2D) {
        postMouse(.leftMouseUp, at: point)
    }

    /// Public CGEvent mouse API. Synthetic events approximate a physical click / drag; they
    /// are not identical to a real trackpad (e.g. no pressure, no force click).
    private func postMouse(_ type: CGEventType, at point: Point2D) {
        guard point.isFinite else { return }
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: CGPoint(x: point.x, y: point.y),
            mouseButton: .left
        ) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.post(tap: .cghidEventTap)
    }

    /// One scroll step as a continuous, pixel-based scroll-wheel event with trackpad-style
    /// phase fields (public CGEvent API). This approximates a trackpad; it is NOT identical to
    /// a real trackpad gesture, and how each app reacts must be validated on the Mac.
    ///
    /// Sign: the Core's delta > 0 means "content moves down" (it follows a hand moving down).
    /// For a scroll-wheel event, a positive wheel value moves the content down. Whether macOS
    /// applies the "Natural scrolling" preference to synthetic events is not verified: the
    /// `inverted` setting flips it if the physical test shows the opposite.
    private func postScroll(_ scroll: ScrollAction, inverted: Bool) {
        let value = inverted ? -scroll.delta : scroll.delta
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: Int32(clamping: value),
            wheel2: 0,
            wheel3: 0
        ) else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Self.scrollPhaseValue(scroll.phase))
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Self.momentumPhaseValue(scroll.momentum))
        event.post(tap: .cghidEventTap)
    }

    /// CGScrollPhase raw values: began 1, changed 2, ended 4 (0 = none, e.g. momentum steps).
    private static func scrollPhaseValue(_ phase: ScrollPhase?) -> Int64 {
        switch phase {
        case .began: 1
        case .changed: 2
        case .ended: 4
        case nil: 0
        }
    }

    /// CGMomentumScrollPhase raw values: none 0, begin 1, continue 2, end 3.
    private static func momentumPhaseValue(_ phase: MomentumPhase) -> Int64 {
        switch phase {
        case .none: 0
        case .began: 1
        case .changed: 2
        case .ended: 3
        }
    }
}
