import Foundation

/// Hardware-independent commands produced by the gesture layer.
///
/// Positions are normalized DISPLAY coordinates: 0...1, origin top-left,
/// y down. The macOS layer converts them with `ScreenMapper` and posts
/// one CGEvent per action. `clickCount` maps to kCGMouseEventClickState.
/// The mouse cases belong to the Phase 0 click/drag state machine (not wired; PHASE 3B+).
public enum InteractionAction: Equatable, Sendable {
    case moveCursor(to: Point2D)
    case mouseDown(at: Point2D, clickCount: Int)
    case mouseDrag(to: Point2D)
    case mouseUp(at: Point2D, clickCount: Int)
    /// PHASE 3A-2: one scroll step (gesture or momentum), see `ScrollAction`.
    case scroll(ScrollAction)
}

/// Phase of a direct (finger-driven) scroll gesture, like a trackpad's.
public enum ScrollPhase: String, Equatable, Sendable {
    case began
    case changed
    case ended
}

/// Phase of the inertia that may follow a scroll gesture.
public enum MomentumPhase: String, Equatable, Sendable {
    case none
    case began
    case changed
    case ended
}

/// Semantic scroll step. `delta` is how far the CONTENT moves, in points, in the user's view:
/// positive = the content moves DOWN, i.e. it follows a hand moving down ("content follows the
/// finger"). Whole points only: the fractional remainder is carried by ScrollController, so
/// slow scrolling is never lost. How macOS encodes it (sign, units, phases) is the adapter's job.
public struct ScrollAction: Equatable, Sendable {
    public var delta: Int
    /// Set during the gesture; nil for momentum steps.
    public var phase: ScrollPhase?
    public var momentum: MomentumPhase

    public init(delta: Int, phase: ScrollPhase?, momentum: MomentumPhase = .none) {
        self.delta = delta
        self.phase = phase
        self.momentum = momentum
    }
}
