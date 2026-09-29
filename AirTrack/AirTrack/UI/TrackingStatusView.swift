import AirTrackCore
import SwiftUI

/// Diagnostic side panel: camera, permission, tracking, per-joint detection and performance.
struct TrackingStatusView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("AirTrack").font(.title2.bold())
                Text("PHASE 1.1 · Camera + Vision debug").font(.caption).foregroundStyle(.secondary)

                section("Estado") {
                    row("Camera", model.cameraStatus.label, color: cameraColor)
                    row("Tracking", model.trackingLabel, color: trackingColor)
                    row("Hands", "\(model.handCount)")
                    ForEach(Array(model.hands.enumerated()), id: \.offset) { index, hand in
                        Text(handSummary(hand, number: index + 1))
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    if let tip = model.primaryHand?.position(of: .indexTip) {
                        row("Index tip (x, y)", String(format: "%.2f, %.2f", tip.x, tip.y))
                        Text("y: 0 = arriba, 1 = abajo. Subir la mano debe BAJAR y.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if !model.rejections.isEmpty {
                        Text("Rechazadas: " + model.rejections.map(rejectionLabel).joined(separator: ", "))
                            .font(.caption2).foregroundStyle(.orange)
                    }
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
                    row("Superseded frames", "\(model.metrics.supersededFrames)")
                    row("Camera drops", "\(model.metrics.cameraDroppedFrames)")
                    Text("Capture → HandState no incluye el tiempo de pantalla: no es latencia end-to-end. Superseded = frames sustituidos por uno más nuevo antes de llegar a Vision (esperado).")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                section("Landmarks · mano 1") {
                    landmarkRow(.wrist, label: "wrist", color: .white)
                    ForEach(Finger.allCases, id: \.self) { finger in
                        fingerRow(finger)
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

    private func landmarkRow(_ joint: HandJoint, label: String, color: Color) -> some View {
        let landmark = model.primaryHand?.landmarks[joint]
        return HStack {
            Image(systemName: landmark == nil ? "circle" : "circle.fill").foregroundStyle(color)
            Text(label).font(.caption.monospaced())
            Spacer()
            Text(landmark.map { String(format: "%.2f", $0.confidence) } ?? "—")
                .font(.caption.monospaced()).foregroundStyle(.secondary)
        }
    }

    /// One row per finger: a dot per joint (proximal → tip) and the weakest confidence.
    private func fingerRow(_ finger: Finger) -> some View {
        let joints = Array(HandSkeleton.chain(for: finger).dropFirst())
        let landmarks = joints.map { model.primaryHand?.landmarks[$0] }
        let color = HandDebugOverlay.fingerColors[finger] ?? .white
        let weakest = landmarks.compactMap { $0?.confidence }.min()
        return HStack {
            HStack(spacing: 2) {
                ForEach(0..<landmarks.count, id: \.self) { i in
                    Image(systemName: landmarks[i] == nil ? "circle" : "circle.fill")
                        .font(.caption2).foregroundStyle(color)
                }
            }
            Text(finger.rawValue).font(.caption.monospaced())
            Spacer()
            Text(weakest.map { String(format: "min %.2f", $0) } ?? "—")
                .font(.caption.monospaced()).foregroundStyle(.secondary)
        }
    }

    private func handSummary(_ hand: HandState, number: Int) -> String {
        let side = switch hand.chirality {
        case .left: "L"
        case .right: "R"
        case .unknown: "?"
        }
        let confidence = String(format: "%.2f", hand.confidence)
        return "Mano \(number) · \(side) · conf \(confidence) · \(hand.landmarks.count)/21 joints"
    }

    private func rejectionLabel(_ reason: HandRejectionReason) -> String {
        switch reason {
        case .lowHandConfidence: "confianza baja"
        case let .missingRequiredJoint(joint): "falta \(joint.rawValue)"
        case let .tooFewJoints(count): "solo \(count) joints"
        case .handTooSmall: "mano demasiado pequeña"
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
