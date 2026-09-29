import AirTrackCore
import AppKit
import QuartzCore

/// Draws HandState landmarks. Only the joints AirTrack actually uses are drawn, so the
/// overlay validates the Vision → HandState mapping itself, not Vision's raw output.
///
/// Colors: index tip green, thumb tip orange, other joints white, index chain as a line,
/// dashed thumb–index line (the pinch distance used later in PHASE 3).
final class HandDebugOverlay: CALayer {
    private let bones = CAShapeLayer()
    private let pinchLine = CAShapeLayer()
    private let joints = CAShapeLayer()
    private let indexTip = CAShapeLayer()
    private let thumbTip = CAShapeLayer()

    private static let indexChain: [HandJoint] = [.wrist, .indexMCP, .indexPIP, .indexDIP, .indexTip]

    override init() {
        super.init()
        configure(bones, stroke: NSColor.white.withAlphaComponent(0.8), fill: nil, width: 2)
        configure(pinchLine, stroke: NSColor.systemOrange, fill: nil, width: 2)
        pinchLine.lineDashPattern = [4, 4]
        configure(joints, stroke: nil, fill: NSColor.white, width: 0)
        configure(indexTip, stroke: NSColor.black, fill: NSColor.systemGreen, width: 1.5)
        configure(thumbTip, stroke: NSColor.black, fill: NSColor.systemOrange, width: 1.5)
        for layer in [bones, pinchLine, joints, indexTip, thumbTip] { addSublayer(layer) }
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// `convert` maps a HandState point (0…1, top-left, unmirrored) into this layer's space.
    func draw(hand: HandState?, convert: (Point2D) -> CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        for layer in [bones, pinchLine, joints, indexTip, thumbTip] { layer.frame = bounds }

        guard let hand, hand.isTracked else {
            for layer in [bones, pinchLine, joints, indexTip, thumbTip] { layer.path = nil }
            return
        }

        func point(_ joint: HandJoint) -> CGPoint? {
            hand.position(of: joint).map(convert)
        }

        let bonePath = CGMutablePath()
        var previous: CGPoint?
        for joint in Self.indexChain {
            guard let current = point(joint) else {
                previous = nil
                continue
            }
            if let previous {
                bonePath.move(to: previous)
                bonePath.addLine(to: current)
            }
            previous = current
        }
        bones.path = bonePath

        let pinchPath = CGMutablePath()
        if let thumb = point(.thumbTip), let index = point(.indexTip) {
            pinchPath.move(to: thumb)
            pinchPath.addLine(to: index)
        }
        pinchLine.path = pinchPath

        let jointPath = CGMutablePath()
        for joint in HandJoint.allCases where joint != .indexTip && joint != .thumbTip {
            if let p = point(joint) { jointPath.addEllipse(in: Self.dot(at: p, radius: 4)) }
        }
        joints.path = jointPath

        indexTip.path = point(.indexTip).map { CGPath(ellipseIn: Self.dot(at: $0, radius: 7), transform: nil) }
        thumbTip.path = point(.thumbTip).map { CGPath(ellipseIn: Self.dot(at: $0, radius: 7), transform: nil) }
    }

    private func configure(_ layer: CAShapeLayer, stroke: NSColor?, fill: NSColor?, width: CGFloat) {
        layer.strokeColor = stroke?.cgColor
        layer.fillColor = fill?.cgColor ?? NSColor.clear.cgColor
        layer.lineWidth = width
    }

    private static func dot(at p: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
    }
}
