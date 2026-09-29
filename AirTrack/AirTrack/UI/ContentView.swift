import SwiftUI

struct ContentView: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            PreviewPane(model: model)
                .frame(minWidth: 640, maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            TrackingStatusView(model: model)
                .frame(width: 300)
        }
        .task { await model.activate() }
        .onDisappear { model.stop() }
    }
}

/// Separate view so per-frame landmark updates only re-render the preview, not the panel layout.
private struct PreviewPane: View {
    let model: AppModel

    var body: some View {
        ZStack {
            Color.black
            CameraPreviewView(session: model.session, hand: model.hand, mirrored: model.mirrorPreview)
            if model.cameraStatus != .running {
                Text(placeholder)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding()
            }
        }
    }

    private var placeholder: String {
        switch model.cameraStatus {
        case .unknown, .ready: "Iniciando cámara…"
        case .permissionRequired: "Camera: Permission Required"
        case .stopped: "Camera: Stopped"
        case .disconnected: "Camera: Disconnected — reconéctala y pulsa Reintentar"
        case let .error(message): "Camera: Error — \(message)"
        case .running: ""
        }
    }
}
