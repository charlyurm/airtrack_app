import AirTrackCore
import SwiftUI

/// Draws every validated hand over the preview.
///
/// Coordinates: SwiftUI's space is ALWAYS origin top-left, y down, which is also HandState's
/// convention, so the only transform is AirTrackCore's PreviewGeometry (letterboxing + optional
/// mirror). No AVFoundation/AppKit coordinate conversion is involved (Phase 1.1 fix).
///
/// Each finger has its own color so a chain on the wrong finger is obvious:
/// thumb orange · index green · middle blue · ring purple · pinky pink. The second hand is
/// drawn dimmer and both hands are labelled "1"/"2" (+ L/R if Vision reported chirality).
struct HandDebugOverlay: View {
    let hands: [HandState]
    let mirrored: Bool

    static let fingerColors: [Finger: Color] = [
        .thumb: .orange, .index: .green, .middle: .blue, .ring: .purple, .pinky: .pink,
    ]

    var body: some View {
        Canvas { context, size in
            for (index, hand) in hands.enumerated() {
                draw(hand, number: index + 1, in: &context, size: size)
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(_ hand: HandState, number: Int, in context: inout GraphicsContext, size: CGSize) {
        func point(_ joint: HandJoint) -> CGPoint? {
            guard let p = hand.position(of: joint),
                  let v = PreviewGeometry.viewPoint(
                      for: p,
                      imageAspectRatio: hand.imageAspectRatio,
                      viewWidth: Double(size.width),
                      viewHeight: Double(size.height),
                      mirrored: mirrored
                  ) else { return nil }
            return CGPoint(x: v.x, y: v.y)
        }

        let opacity = number == 1 ? 1.0 : 0.6
        for finger in Finger.allCases {
            let color = (Self.fingerColors[finger] ?? .white).opacity(opacity)
            let chain = HandSkeleton.chain(for: finger)
            var path = Path()
            var previous: CGPoint?
            for joint in chain {
                guard let current = point(joint) else {
                    previous = nil
                    continue
                }
                if let previous {
                    path.move(to: previous)
                    path.addLine(to: current)
                }
                previous = current
            }
            context.stroke(path, with: .color(color), lineWidth: 3)

            for joint in chain.dropFirst() {
                guard let p = point(joint) else { continue }
                let isTip = joint == HandSkeleton.tip(of: finger)
                let radius: CGFloat = isTip ? 7 : 4
                let dot = Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
                context.fill(dot, with: .color(color))
                if isTip { context.stroke(dot, with: .color(.black.opacity(opacity)), lineWidth: 1.5) }
            }
        }

        if let wrist = point(.wrist) {
            let dot = Path(ellipseIn: CGRect(x: wrist.x - 5, y: wrist.y - 5, width: 10, height: 10))
            context.fill(dot, with: .color(.white.opacity(opacity)))
            let label = chiralityLabel(hand.chirality).map { "\(number) \($0)" } ?? "\(number)"
            context.draw(
                Text(label).font(.caption.bold()).foregroundColor(.white),
                at: CGPoint(x: wrist.x, y: wrist.y + 16)
            )
        }
    }

    private func chiralityLabel(_ chirality: HandChirality) -> String? {
        switch chirality {
        case .left: "L"
        case .right: "R"
        case .unknown: nil
        }
    }
}
