import AirTrackCore
import SwiftUI

/// Diagnostic side panel: camera, permission, tracking, per-joint detection and performance.
struct TrackingStatusView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("AirTrack").font(.title2.bold())
                Text("PHASE 3A · Cursor + scroll debug").font(.caption).foregroundStyle(.secondary)

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

                cursorSection

                gestureSection

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

    // MARK: Cursor (PHASE 2)

    private var cursorSection: some View {
        section("Cursor") {
            Toggle("Cursor Control", isOn: Binding(
                get: { model.cursorEnabled },
                set: { model.setCursorEnabled($0) }
            ))
            row("Cursor", cursorStateLabel, color: cursorStateColor)
            row("Permission", model.accessibilityGranted ? "READY" : "REQUIRED",
                color: model.accessibilityGranted ? .green : .orange)
            if !model.accessibilityGranted {
                Text("AirTrack necesita permiso de Accesibilidad para controlar el cursor y generar eventos de entrada.")
                    .font(.caption)
                HStack {
                    Button(model.accessibilityRequested ? "Abrir Configuración" : "Conceder permiso") {
                        model.requestAccessibility()
                    }
                    Button("Comprobar de nuevo") { model.recheckAccessibility() }
                }
                if model.accessibilityRequested {
                    Text("Actívalo en Privacidad y seguridad → Accesibilidad y vuelve a AirTrack: se comprueba solo al volver.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            accessibilityDiagnostics
            Button(model.cursorPaused ? "Reanudar (⌃⌥⌘A)" : "Pausar (⌃⌥⌘A)") { model.toggleCursorPause() }
                .keyboardShortcut("a", modifiers: [.control, .option, .command])
                .disabled(!model.cursorEnabled)
            row("Primary hand", model.hands.isEmpty ? "—" : "1 de \(model.hands.count)")
            row("Pointer", pointerLabel, color: pointerColor)
            row("Index confidence", format(model.pointer.indexConfidence, "%.2f"))
            row("Mapped cursor", model.cursor.map { String(format: "%.0f, %.0f pt", $0.screen.x, $0.screen.y) } ?? "—")
            row("Finger speed", format(model.cursor?.speed, "%.2f scr/s"))
            row("Smoothing now", format(model.cursor?.smoothing, "%.2f"))
            row("Gaps bridged / losses", "\(model.bridgedGaps) / \(model.pointerLosses)")
            row("Active area", activeAreaLabel)
            slider("Sensitivity", value: settingBinding(\.cursorSensitivity), range: CursorMapper.sensitivityRange, format: "%.2f×")
            slider("Smoothing (rest)", value: settingBinding(\.cursorSmoothing), range: 0...0.9, format: "%.2f")
            slider("Speed response", value: settingBinding(\.cursorSpeedResponse), range: AdaptiveCursorSmoother.speedResponseRange, format: "%.1f")
            slider("Dead zone", value: settingBinding(\.cursorDeadZone), range: 0...0.02, format: "%.3f")
            slider("Reacquisition glide", value: settingBinding(\.cursorReacquisitionBlend), range: 0...0.5, format: "%.2f s")
            Toggle("Peripheral tracking", isOn: settingBinding(\.cursorPeripheralTracking))
            Text("Smoothing now: 0 = cursor pegado al dedo, cerca de 1 = muy suavizado. Speed response 0 = suavizado fijo (Phase 2). Pointer: FULL mano completa · PARTIAL mano parcial · INDEX solo el índice · HOLD hueco breve (cursor quieto) · LOST.")
                .font(.caption2).foregroundStyle(.secondary)
            Text("Para soltar el cursor: saca la mano del cuadro, pulsa Pausar o apaga Cursor Control. Solo la mano 1 mueve el cursor. Pantalla: la principal.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var cursorStateLabel: String {
        switch model.cursorState {
        case .off: "OFF"
        case .paused: "PAUSED"
        case .waitingForPermission: "WAITING FOR PERMISSION"
        case .waitingForHand: "WAITING FOR HAND"
        case .active: "ACTIVE"
        }
    }

    private var cursorStateColor: Color {
        switch model.cursorState {
        case .active: .green
        case .off: .secondary
        case .paused, .waitingForHand: .orange
        case .waitingForPermission: .red
        }
    }

    /// What macOS evaluates for THIS process. If System Settings shows AirTrack allowed but
    /// both answers are "no", the entry belongs to another build (see PERMISSIONS.md).
    private var accessibilityDiagnostics: some View {
        let d = model.accessibilityDiagnostics
        return DisclosureGroup("Diagnóstico de Accesibilidad") {
            VStack(alignment: .leading, spacing: 4) {
                row("AX trusted", d.processTrusted ? "sí" : "no", color: d.processTrusted ? .green : .orange)
                row("Post events", d.canPostEvents ? "sí" : "no", color: d.canPostEvents ? .green : .orange)
                row("Bundle ID", d.bundleIdentifier)
                row("Firma", d.signatureLabel)
                Text(d.executablePath)
                    .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if d.signature == .adHoc {
                    Text("Firma ad-hoc: macOS asocia el permiso a ESTE binario exacto. Tras cada recompilación, la entrada de Accesibilidad puede seguir activada pero ya no aplicar. Quítala con «−» y vuelve a pulsar «Conceder permiso», o firma con tu Personal Team.")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
        }
        .font(.caption)
    }

    // MARK: Gestures (PHASE 3A)

    private var gestureSection: some View {
        let i = model.interaction
        return section("Gestos (PHASE 3A)") {
            row("Pose", poseLabel(i.pose), color: i.pose == .unknown ? .secondary : .primary)
            if i.rawPose != i.pose {
                Text("raw: \(poseLabel(i.rawPose))").font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
            row("Dedos T I M R L", fingerLabel(i.features))
            row("Escala mano", format(i.features?.scale, "%.3f"))
            row("Velocidad mano", String(format: "%.2f esc/s", i.handSpeed))
            row("Eje", i.axis.rawValue.uppercased())
            row("Candidato", candidateLabel(i.candidate))
            row("Intent", i.intent.map(kindLabel) ?? "—", color: i.intent == nil ? .secondary : .green)
            row("Lifecycle", i.lifecycle.rawValue.uppercased())
            row("Cursor policy", i.cursorPolicy == .frozen ? "FROZEN" : "FOLLOW",
                color: i.cursorPolicy == .frozen ? .orange : .primary)
            row("Scroll", scrollStateLabel(i), color: i.scrollState == .idle ? .secondary : .green)
            row("Scroll speed", String(format: "%.0f pt/s", i.scrollSpeed))
            row("Scroll delta", "\(i.scrollDelta) pt")
            Toggle("Scroll con gestos", isOn: settingBinding(\.scrollGesturesEnabled))
            Toggle("Invertir dirección del scroll", isOn: settingBinding(\.scrollDirectionInverted))
            Text("E = extendido · B = doblado · ? = incierto. Escala y velocidad en tamaños de mano. Scroll: ☝️🖕 o 🖐️ moviendo en vertical; el cursor se congela mientras dura. Sin «Scroll con gestos» (o sin Cursor Control) solo se observa: no se envía nada.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func scrollStateLabel(_ i: InteractionFrame) -> String {
        let state = switch i.scrollState {
        case .idle: "IDLE"
        case .scrolling: "SCROLLING"
        case .momentum: "INERTIA"
        }
        return i.scrollState == .idle ? state : state + (i.liveOutput ? " · LIVE" : " · SHADOW")
    }

    private func poseLabel(_ pose: HandPose) -> String {
        switch pose {
        case .pointing: "POINTING ☝️"
        case .twoFinger: "TWO_FINGER ☝️🖕"
        case .openHand: "OPEN_HAND 🖐️"
        case .fourFinger: "FOUR_FINGER"
        case .pinch: "PINCH 🤏"
        case .unknown: "UNKNOWN"
        }
    }

    private func fingerLabel(_ features: HandFeatures?) -> String {
        guard let features else { return "—" }
        return Finger.allCases.map { finger in
            switch features.state(of: finger) {
            case .extended: "E"
            case .bent: "B"
            case .unknown: "?"
            }
        }.joined(separator: " ")
    }

    private func kindLabel(_ kind: GestureKind) -> String {
        switch kind {
        case .twoFingerScroll: "SCROLL 2 dedos"
        case .openHandScroll: "SCROLL mano abierta"
        }
    }

    private func candidateLabel(_ candidate: GestureCandidate?) -> String {
        guard let candidate else { return "—" }
        return "\(kindLabel(candidate.kind)) · \(Int((candidate.evidence * 100).rounded())) %"
    }

    private var pointerLabel: String {
        switch model.pointer.mode {
        case .full: "FULL"
        case .partial: "PARTIAL"
        case .indexContinuity: "INDEX"
        case .holding: "HOLD"
        case .lost: "LOST"
        }
    }

    private var pointerColor: Color {
        switch model.pointer.mode {
        case .full: .green
        case .partial: .yellow
        case .indexContinuity, .holding: .orange
        case .lost: .secondary
        }
    }

    private var activeAreaLabel: String {
        let area = model.settings.cursorMapper.validActiveArea
        return String(format: "x %.2f–%.2f · y %.2f–%.2f", area.minX, area.maxX, area.minY, area.maxY)
    }

    private func settingBinding<Value>(_ keyPath: WritableKeyPath<AirTrackSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { newValue in
                var settings = model.settings
                settings[keyPath: keyPath] = newValue
                model.updateSettings(settings)
            }
        )
    }

    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption)
                Spacer()
                Text(String(format: format, value.wrappedValue)).font(.caption.monospaced())
            }
            Slider(value: value, in: range)
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
