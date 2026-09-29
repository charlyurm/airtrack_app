import AppKit
import AVFoundation
import SwiftUI

/// Live camera preview only. Landmarks are drawn by HandDebugOverlay on top, in SwiftUI.
struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool

    func makeNSView(context: Context) -> PreviewNSView {
        PreviewNSView(session: session)
    }

    func updateNSView(_ view: PreviewNSView, context: Context) {
        view.setMirrored(mirrored)
    }
}

/// Layer-hosting view whose layer IS the AVCaptureVideoPreviewLayer.
///
/// `.resizeAspect` = scale to fit, centered, letterboxed. HandDebugOverlay reproduces exactly
/// that placement with AirTrackCore's PreviewGeometry, so this view only has to show video.
final class PreviewNSView: NSView {
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private var mirrored = true

    init(session: AVCaptureSession) {
        super.init(frame: .zero)
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspect
        previewLayer.backgroundColor = NSColor.black.cgColor
        layer = previewLayer
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setMirrored(_ mirrored: Bool) {
        self.mirrored = mirrored
        applyMirroring()
    }

    override func layout() {
        super.layout()
        // The preview connection appears once the session is configured; re-apply then.
        applyMirroring()
    }

    private func applyMirroring() {
        guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        if connection.isVideoMirrored != mirrored {
            connection.isVideoMirrored = mirrored
        }
    }
}
