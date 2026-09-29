import Foundation

/// PHASE 3B: the drag cursor and the primary-button ledger of the macOS side.
///
/// Positions are display-normalized (0…1, top-left, y down), the space CursorController already
/// produces: the index position fed here IS the Phase 2.1 cursor mapping (active area, mirror,
/// dead zone, sensitivity, adaptive smoothing), so drag adds no second mapping or smoothing.
///
/// Anchor (fixed for the whole drag, never recomputed):
///
///     offset     = anchorCursor - anchorIndex      (first index after the press)
///     dragCursor = clamp(index + offset)
///
/// so the dragged object does not jump when the drag starts and then follows the index.
///
/// Ledger: `press` and `release` are the only way the button changes, so a second press is
/// ignored, a release without a press yields nothing, and `release` after any path (end of
/// drag, pause, permission, camera, shutdown) tells whether a mouseUp is still owed.
public struct DragController: Sendable {
    public private(set) var isButtonDown = false
    /// Cursor position when the button went down.
    public private(set) var anchorCursor: Point2D?
    /// anchorCursor - anchorIndex, fixed by the first index sample of the drag.
    public private(set) var offset: Point2D?
    /// Last position the drag was posted at (where the button will be released).
    public private(set) var position: Point2D?

    public init() {}

    /// mouseDown at the current cursor. Returns false (nothing to post) when already down or
    /// the position is invalid.
    public mutating func press(at cursor: Point2D) -> Bool {
        guard !isButtonDown, cursor.isFinite else { return false }
        let start = Rect2D.unit.clamp(cursor)
        isButtonDown = true
        anchorCursor = start
        offset = nil
        position = start
        return true
    }

    /// Drag position for this frame's index (display-normalized cursor mapping). nil when the
    /// button is not down or the sample is invalid (nothing to post). The first sample after
    /// the press fixes the anchor and returns the press position: no jump.
    public mutating func follow(index: Point2D) -> Point2D? {
        guard isButtonDown, index.isFinite, let anchorCursor else { return nil }
        let fixed: Point2D
        if let offset {
            fixed = offset
        } else {
            fixed = anchorCursor - index
            offset = fixed
        }
        let next = Rect2D.unit.clamp(index + fixed)
        position = next
        return next
    }

    /// mouseUp. Returns where to release, or nil when the button is not down (no mouseUp
    /// without a mouseDown). Idempotent.
    public mutating func release() -> Point2D? {
        guard isButtonDown else { return nil }
        // press always sets both; the fallback only keeps the mouseUp unconditional.
        let at = position ?? anchorCursor ?? Point2D(x: 0.5, y: 0.5)
        isButtonDown = false
        anchorCursor = nil
        offset = nil
        position = nil
        return at
    }
}
