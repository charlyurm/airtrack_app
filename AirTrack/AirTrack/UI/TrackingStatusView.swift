import AirTrackCore
import SwiftUI

/// Diagnostic side panel: camera, permission, tracking, per-joint detection and performance.
struct TrackingStatusView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("AirTrack").font(.title2.bold())
                Text("PHASE 1 · Camera + Vision debug").font(.caption).foregroundStyle(.secondary)

                section("Estado") {
                    row("Camera", model.cameraStatus.label, color: cameraColor)
                    row("Tracking", model.trackingLabel, color: trackingColor)
                    row("Hands", "\(model.handCount)")
                    if case let .error(message) = model.cameraStatus {
                        Text(message).font(.caption).foregroundStyle(.red)
                    }
                }

                permissionSection

                section("Cámara") {
                    Picker("Cámara", selection: $model.selectedCameraID) {
                        ForEach(model.cameras) { camera in
                            Text(camera.name).tag(Optional(camera.id))
                        }
                    }
                    .labelsHidden()
                    .onChange(of: model.selectedCameraID) { _, id in model.selectCamera(id) }
                    Toggle("Espejar preview", isOn: $model.mirrorPreview)
                    HStack {
                        Button("Start") { model.start() }
                            .disabled(model.cameraStatus == .running || model.permission != .authorized)
                        Button("Stop") { model.stop() }
                            .disabled(model.cameraStatus != .running)
                        Button("Reintentar") { Task { await model.retry() } }
                    }
                }

                section("Rendimiento") {
                    row("Camera FPS", format(model.metrics.cameraFPS, "%.1f"))
                    row("Vision FPS", format(model.metrics.visionFPS, "%.1f"))
                    row("Vision processing", format(model.metrics.visionProcessingMs, "%.1f ms"))
                    row("Capture → HandState", format(model.metrics.captureToHandStateMs, "%.0f ms"))
                    row("Dropped frames", "\(model.metrics.droppedFrames)")
                    Text("Capture → HandState no incluye el tiempo de pantalla: no es latencia end-to-end.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                section("Landmarks") {
                    ForEach(HandJoint.allCases, id: \.self) { joint in
                        landmarkRow(joint)
                    }
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        switch model.permission {
        case .authorized:
            EmptyView()
        case .notDetermined:
            section("Permiso de cámara") {
                Text("AirTrack todavía no ha pedido permiso de cámara.").font(.caption)
                Button("Pedir permiso") { Task { await model.retry() } }
            }
        case .denied, .restricted:
            section("Permiso de cámara") {
                Text("AirTrack necesita la cámara para detectar los movimientos de tu mano. Las imágenes se procesan solo en este Mac.")
                    .font(.caption)
                Text("Actívalo en Configuración del Sistema → Privacidad y seguridad → Cámara y pulsa Reintentar.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Abrir Configuración del Sistema") { model.openCameraSettings() }
            }
        }
    }

    private func landmarkRow(_ joint: HandJoint) -> some View {
        let landmark = model.hand?.landmarks[joint]
        return HStack {
            Image(systemName: landmark == nil ? "circle" : "circle.fill")
                .foregroundStyle(landmark == nil ? Color.secondary : Color.green)
            Text(joint.rawValue).font(.caption.monospaced())
            Spacer()
            Text(landmark.map { String(format: "%.2f", $0.confidence) } ?? "—")
                .font(.caption.monospaced()).foregroundStyle(.secondary)
        }
    }

    private var cameraColor: Color {
        switch model.cameraStatus {
        case .running: .green
        case .ready, .stopped, .unknown: .secondary
        case .permissionRequired, .disconnected: .orange
        case .error: .red
        }
    }

    private var trackingColor: Color {
        switch model.trackingLabel {
        case "HAND DETECTED": .green
        case "LOST": .orange
        default: .secondary
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption.bold()).foregroundStyle(.secondary)
            content()
        }
    }

    private func row(_ label: String, _ value: String, color: Color = .primary) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).monospacedDigit().bold().foregroundStyle(color)
        }
    }

    private func format(_ value: Double?, _ pattern: String) -> String {
        guard let value else { return "—" }
        return String(format: pattern, value)
    }
}
