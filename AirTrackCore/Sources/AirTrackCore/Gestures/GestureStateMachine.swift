import Foundation

public struct GestureConfiguration: Equatable, Sendable, Codable {
    /// Max time from a click's release to the next pinch start for a double click.
    public var doubleClickInterval: TimeInterval
    /// Max anchor distance (normalized display units) between the two clicks of a double click.
    public var doubleClickMaxDistance: Double
    /// Holding a pinch this long turns the click candidate into a drag.
    public var dragHoldDuration: TimeInterval
    /// Moving this far (normalized display units) from the anchor turns the candidate into a drag
    /// immediately. Pinch-induced fingertip drift must stay below it.
    public var dragMovementThreshold: Double
    /// The click anchor is the cursor position this long BEFORE the pinch was confirmed,
    /// i.e. before the fingers started closing and dragging the index tip.
    public var anchorLookback: TimeInterval
    /// Short tracking dropouts shorter than this are ignored (no release mid-drag).
    public var trackingLossGracePeriod: TimeInterval

    /// Starting values only — they MUST be tuned on real hardware (REQUIRES MACOS).
    public init(
        doubleClickInterval: TimeInterval = 0.4,
        doubleClickMaxDistance: Double = 0.02,
        dragHoldDuration: TimeInterval = 0.3,
        dragMovementThreshold: Double = 0.03,
        anchorLookback: TimeInterval = 0.07,
        trackingLossGracePeriod: TimeInterval = 0.15
    ) {
        self.doubleClickInterval = doubleClickInterval
        self.doubleClickMaxDistance = doubleClickMaxDistance
        self.dragHoldDuration = dragHoldDuration
        self.dragMovementThreshold = dragMovementThreshold
        self.anchorLookback = anchorLookback
        self.trackingLossGracePeriod = trackingLossGracePeriod
    }
}

public enum GesturePhase: Equatable, Sendable {
    /// No usable tracking, or paused. Nothing is emitted.
    case idle
    /// Index finger moves the cursor.
    case pointing
    /// Pinch confirmed; cursor frozen at `anchor`. Nothing has been sent to the OS yet.
    case clickCandidate(anchor: Point2D, startedAt: TimeInterval, clickCount: Int)
    /// Mouse button is down; cursor follows the finger.
    case dragging(position: Point2D)
}

public enum CancellationReason: Equatable, Sendable {
    case trackingLost
    case paused
}

/// Semantic events for logging and UI. Maps to the approved design:
/// PINCH_START = pinchStarted, CLICK = clicked, DRAG = dragStarted, RELEASE = dragEnded.
public enum GestureEvent: Equatable, Sendable {
    case pinchStarted(clickCount: Int)
    case clicked(clickCount: Int)
    case dragStarted
    case dragEnded
    case cancelled(CancellationReason)
}

public enum GestureInput: Equatable, Sendable {
    /// `cursor` is the smoothed, normalized display position of the index tip.
    case frame(timestamp: TimeInterval, cursor: Point2D, isPinched: Bool)
    case trackingLost(timestamp: TimeInterval)
    case paused(timestamp: TimeInterval)
}

public struct GestureOutput: Equatable, Sendable {
    public var actions: [InteractionAction]
    public var events: [GestureEvent]

    public init(actions: [InteractionAction] = [], events: [GestureEvent] = []) {
        self.actions = actions
        self.events = events
    }

    public static let empty = GestureOutput()
}

/// Deterministic click / double-click / drag state machine.
///
/// Key rules:
/// - mouseDown is deferred until the gesture is resolved: release → click (down+up at the
///   anchor), hold or large move → drag (down at the anchor, then drags). So a cancelled
///   click candidate never reaches the OS.
/// - The click lands on the anchor captured before the fingers closed (stabilization).
/// - A held pinch always drags with clickCount 1: it is never a double click.
/// - Tracking loss / pause while dragging always sends mouseUp (no stuck button).
/// - After loss / pause, the hand must open once before a new pinch is accepted.
public struct GestureStateMachine: Sendable {
    private struct Sample: Sendable {
        var time: TimeInterval
        var position: Point2D
    }

    private struct ClickRecord: Sendable {
        var releasedAt: TimeInterval
        var position: Point2D
        var clickCount: Int
    }

    private static let historyDuration: TimeInterval = 0.5

    public var configuration: GestureConfiguration
    public private(set) var phase: GesturePhase = .idle
    public private(set) var requiresOpenHandBeforePinch = true

    private var history: [Sample] = []
    private var lastEmittedCursor: Point2D?
    private var lastClick: ClickRecord?
    private var trackingLostSince: TimeInterval?

    public init(configuration: GestureConfiguration = GestureConfiguration()) {
        self.configuration = configuration
    }

    public mutating func update(_ input: GestureInput) -> GestureOutput {
        switch input {
        case let .frame(timestamp, cursor, isPinched):
            return handleFrame(time: timestamp, cursor: cursor, isPinched: isPinched)
        case let .trackingLost(timestamp):
            return handleTrackingLost(time: timestamp)
        case .paused:
            return cancel(reason: .paused)
        }
    }

    private mutating func handleFrame(time: TimeInterval, cursor: Point2D, isPinched: Bool) -> GestureOutput {
        trackingLostSince = nil
        record(time: time, position: cursor)
        var output = GestureOutput()

        switch phase {
        case .idle, .pointing:
            if isPinched && !requiresOpenHandBeforePinch {
                var anchor = position(at: time - configuration.anchorLookback) ?? cursor
                var clickCount = 1
                if let last = lastClick,
                   last.clickCount == 1,
                   time - last.releasedAt <= configuration.doubleClickInterval,
                   anchor.distance(to: last.position) <= configuration.doubleClickMaxDistance {
                    clickCount = 2
                    anchor = last.position
                }
                phase = .clickCandidate(anchor: anchor, startedAt: time, clickCount: clickCount)
                output.events.append(.pinchStarted(clickCount: clickCount))
                emitMove(to: anchor, into: &output)
            } else {
                if !isPinched { requiresOpenHandBeforePinch = false }
                phase = .pointing
                emitMove(to: cursor, into: &output)
            }

        case let .clickCandidate(anchor, startedAt, clickCount):
            if !isPinched {
                output.actions.append(.mouseDown(at: anchor, clickCount: clickCount))
                output.actions.append(.mouseUp(at: anchor, clickCount: clickCount))
                output.events.append(.clicked(clickCount: clickCount))
                lastClick = ClickRecord(releasedAt: time, position: anchor, clickCount: clickCount)
                lastEmittedCursor = anchor
                phase = .pointing
            } else if time - startedAt >= configuration.dragHoldDuration
                        || cursor.distance(to: anchor) >= configuration.dragMovementThreshold {
                output.actions.append(.mouseDown(at: anchor, clickCount: 1))
                output.actions.append(.mouseDrag(to: cursor))
                output.events.append(.dragStarted)
                lastClick = nil
                lastEmittedCursor = cursor
                phase = .dragging(position: cursor)
            }

        case let .dragging(position):
            if !isPinched {
                // Release at the last drag position: fingers opening shift the index tip.
                output.actions.append(.mouseUp(at: position, clickCount: 1))
                output.events.append(.dragEnded)
                lastClick = nil
                phase = .pointing
            } else if cursor != position {
                output.actions.append(.mouseDrag(to: cursor))
                lastEmittedCursor = cursor
                phase = .dragging(position: cursor)
            }
        }
        return output
    }

    private mutating func handleTrackingLost(time: TimeInterval) -> GestureOutput {
        guard phase != .idle else { return .empty }
        let since = trackingLostSince ?? time
        trackingLostSince = since
        if time - since >= configuration.trackingLossGracePeriod {
            return cancel(reason: .trackingLost)
        }
        return .empty
    }

    private mutating func cancel(reason: CancellationReason) -> GestureOutput {
        var output = GestureOutput()
        if case let .dragging(position) = phase {
            output.actions.append(.mouseUp(at: position, clickCount: 1))
        }
        if phase != .idle {
            output.events.append(.cancelled(reason))
        }
        phase = .idle
        requiresOpenHandBeforePinch = true
        history.removeAll()
        lastEmittedCursor = nil
        lastClick = nil
        trackingLostSince = nil
        return output
    }

    private mutating func emitMove(to point: Point2D, into output: inout GestureOutput) {
        guard point != lastEmittedCursor else { return }
        output.actions.append(.moveCursor(to: point))
        lastEmittedCursor = point
    }

    private mutating func record(time: TimeInterval, position: Point2D) {
        history.append(Sample(time: time, position: position))
        let cutoff = time - Self.historyDuration
        if let firstKept = history.firstIndex(where: { $0.time >= cutoff }), firstKept > 0 {
            history.removeFirst(firstKept)
        }
    }

    /// Latest recorded position at or before `time`; the oldest sample if none is that old.
    private func position(at time: TimeInterval) -> Point2D? {
        history.last(where: { $0.time <= time })?.position ?? history.first?.position
    }
}
