import XCTest
@testable import AirTrackCore

/// PHASE 3B: one continuous synthetic hand driving the interaction engine frame by frame
/// (time, position, scale and rotation carry over between pose changes).
struct HandDriver {
    var engine = InteractionEngine()
    var frame = 0
    var center = Point2D(x: 0.5, y: 0.5)
    var scale = 1.0
    var rotation = 0.0
    var jointConfidence = 0.9
    var outputs: InteractionOutputs = .all

    var time: TimeInterval { Double(frame) * InteractionScenario.dt }

    /// - Parameter thumbDistance: overrides the thumb–index tip distance, in hand scales.
    @discardableResult
    mutating func step(
        _ fingers: FingerSet = TestPoses.pointing,
        _ thumb: TestPoses.Thumb = .pinching,
        move: Point2D = .zero,
        mode: PointerTrackingMode = .full,
        omit: Set<HandJoint> = [],
        thumbDistance: Double? = nil
    ) -> InteractionFrame {
        let t = time
        frame += 1
        center = center + move
        var hand = TestPoses.hand(extended: fingers, thumb: thumb, at: t, center: center, scale: scale,
                                  rotation: rotation, jointConfidence: jointConfidence, omit: omit)
        if let thumbDistance { hand = PinchGeometry.opening(hand, to: thumbDistance) }
        let visible = mode.providesPointer ? hand : nil
        return engine.update(pointer: InteractionScenario.pointer(mode, hand: visible, at: t), trackedHand: visible, outputs: outputs)
    }

    mutating func run(
        _ fingers: FingerSet = TestPoses.pointing,
        _ thumb: TestPoses.Thumb = .pinching,
        move: Point2D = .zero,
        count: Int,
        mode: PointerTrackingMode = .full,
        omit: Set<HandJoint> = [],
        thumbDistance: Double? = nil
    ) -> [InteractionFrame] {
        (0..<count).map { _ in step(fingers, thumb, move: move, mode: mode, omit: omit, thumbDistance: thumbDistance) }
    }

    /// Index + thumb pinched (pointing hand, thumb tip on the index tip: 0.126 hand scales).
    mutating func pinch(count: Int, move: Point2D = .zero) -> [InteractionFrame] {
        run(TestPoses.pointing, .pinching, move: move, count: count)
    }

    /// Fingers opened: pointing with the thumb away (L shape, 0.87 hand scales).
    mutating func open(count: Int, move: Point2D = .zero) -> [InteractionFrame] {
        run(TestPoses.pointing, .extended, move: move, count: count)
    }
}

enum PinchGeometry {
    /// Same hand with the thumb tip moved to `distance` hand scales from the index tip.
    static func opening(_ hand: HandState, to distance: Double) -> HandState {
        var hand = hand
        guard let index = hand.landmarks[.indexTip]?.position,
              let scale = HandFeatureExtractor.scale(of: hand) else { return hand }
        let aspect = hand.imageAspectRatio
        let d = distance * scale / 2.0.squareRoot()
        hand.landmarks[.thumbTip]?.position = index + Point2D(x: d / aspect, y: d)
        return hand
    }
}

/// Counts the primary-button events of a run like the macOS ledger would see them.
struct ButtonLedger {
    private(set) var clicks = 0
    private(set) var downs = 0
    private(set) var ups = 0
    private(set) var violations: [String] = []
    var isDown: Bool { downs > ups }

    mutating func record(_ actions: [InteractionAction], at label: String = "") {
        for action in actions {
            switch action {
            case .leftClick:
                if isDown { violations.append("click while the button is down \(label)") }
                clicks += 1
            case .beginDrag:
                if isDown { violations.append("second mouseDown \(label)") }
                downs += 1
            case .endDrag:
                if !isDown { violations.append("mouseUp without mouseDown \(label)") }
                ups += 1
            case .scroll, .moveCursor, .mouseDown, .mouseDrag, .mouseUp:
                break
            }
        }
    }

    mutating func record(_ frames: [InteractionFrame]) {
        for frame in frames { record(frame.actions, at: "t=\(frame.timestamp)") }
    }
}

extension InteractionFrame {
    var clicks: Int { actions.filter { $0 == .leftClick }.count }
    var beginsDrag: Bool { actions.contains(.beginDrag) }
    var endsDrag: Bool { actions.contains(.endDrag) }
}

extension Array where Element == InteractionFrame {
    var clickCount: Int { reduce(0) { $0 + $1.clicks } }
    var dragBegins: Int { filter(\.beginsDrag).count }
    var dragEnds: Int { filter(\.endsDrag).count }
    var buttonActions: [InteractionAction] {
        flatMap(\.actions).filter { $0 == .leftClick || $0 == .beginDrag || $0 == .endDrag }
    }
}
