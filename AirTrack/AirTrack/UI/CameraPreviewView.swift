import AirTrackCore
import AppKit
import AVFoundation
import SwiftUI

/// Live camera preview with the hand landmarks drawn on top.
struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    let hand: HandState?
    let mirrored: Bool

    func makeNSView(context: Context) -> PreviewNSView {
        PreviewNSView(session: session)
    }

    func updateNSView(_ view: PreviewNSView, context: Context) {
        view.update(hand: hand, mirrored: mirrored)
    }
}

/// Layer-hosting view whose layer IS the AVCaptureVideoPreviewLayer.
///
/// Alignment strategy: landmarks (HandState space = unmirrored image, origin top-left, 0…1)
/// are exactly AVFoundation's "capture device point" space for an upright Mac camera, so
/// each point goes through `layerPointConverted(fromCaptureDevicePoint:)`. That conversion
/// applies the preview's video gravity (letterboxing) and mirroring, and the overlay is a
/// sublayer of the same layer, so both share one coordinate system.
final class PreviewNSView: NSView {
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private let overlay = HandDebugOverlay()

    init(session: AVCaptureSession) {
        super.init(frame: .zero)
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspect
        previewLayer.backgroundColor = NSColor.black.cgColor
        layer = previewLayer
        wantsLayer = true
        previewLayer.addSublayer(overlay)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        overlay.frame = previewLayer.bounds
    }

    func update(hand: HandState?, mirrored: Bool) {
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            if connection.isVideoMirrored != mirrored {
                connection.isVideoMirrored = mirrored
            }
        }
        overlay.frame = previewLayer.bounds
        overlay.draw(hand: hand) { [previewLayer] point in
            previewLayer.layerPointConverted(fromCaptureDevicePoint: CGPoint(x: point.x, y: point.y))
        }
    }
}
