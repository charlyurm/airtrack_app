import AirTrackCore
import AppKit
import AVFoundation
import Foundation
import Observation

/// UI state. Lives on the main actor and only receives results: capture and Vision run on
/// their own queues (CameraManager, HandTrackingPipeline).
@MainActor
@Observable
final class AppModel {
    var cameraStatus: CameraStatus = .unknown
    var permission: CameraPermission = CameraPermissionManager.current
    var cameras: [CameraDevice] = []
    var selectedCameraID: String?
    var mirrorPreview = true
    /// Validated hands from the latest processed frame, primary first (HandOrdering). Empty when
    /// no valid hand is visible: never the previous frame's landmarks.
    var hands: [HandState] = []
    /// Raw Vision observations and rejection reasons of the latest frame (diagnostics).
    var candidateCount = 0
    var rejections: [HandRejectionReason] = []
    var metrics = TrackingMetrics()
    /// Whether a hand has been seen since the camera started (distinguishes LOST from NO HAND).
    private(set) var hasSeenHand = false

    // MARK: Cursor control (PHASE 2)

    /// Off at launch: detecting a hand never starts moving the cursor by itself.
    private(set) var cursorEnabled = false
    private(set) var cursorPaused = false
    /// Accessibility permission (hotfix 2.1): state and transitions in AirTrackCore, answer
    /// from the system (AX trusted OR PostEvent allowed) for THIS running process.
    private(set) var accessibility = AccessibilityPermissionTracker(
        isTrusted: AccessibilityPermissionManager.isGranted,
        at: ProcessInfo.processInfo.systemUptime
    )
    /// What macOS sees for this process: both TCC answers, bundle ID, executable, signature.
    private(set) var accessibilityDiagnostics = AccessibilityDiagnostics.current()
    var accessibilityGranted: Bool { accessibility.isGranted }
    /// Whether the macOS prompt was already shown this session (never prompt in a loop).
    var accessibilityRequested: Bool { accessibility.hasShownPrompt }
    private(set) var settings = AirTrackSettings.default
    /// Cursor position posted in the latest frame (nil = cursor not moved).
    private(set) var cursor: CursorUpdate?
    /// PHASE 2.1: pointer decision of the latest frame (full / partial / index / holding / lost).
    private(set) var pointer = PointerObservation.lost(at: 0)
    /// Short gaps bridged by holding (the hand continued without a new acquisition) and real
    /// losses since the camera started. Diagnostics for the Mac validation.
    private(set) var bridgedGaps = 0
    private(set) var pointerLosses = 0
    /// Aspect ratio of the latest processed frame (overlay geometry).
    private(set) var imageAspectRatio = 16.0 / 9.0
    @ObservationIgnored private var activationObserver: NSObjectProtocol?

    let camera: CameraManager
    let pipeline: HandTrackingPipeline

    var session: AVCaptureSession { camera.session }

    /// The hand later phases will use.
    var primaryHand: HandState? { hands.first }

    var trackingLabel: String {
        guard cameraStatus == .running else { return "—" }
        if !hands.isEmpty { return "HAND DETECTED" }
        return hasSeenHand ? "LOST" : "NO HAND"
    }

    var handCount: Int { hands.count }

    var cursorState: CursorControlState {
        .resolve(
            enabled: cursorEnabled,
            paused: cursorPaused,
            permissionGranted: accessibilityGranted,
            handAvailable: cameraStatus == .running && (!hands.isEmpty || pointer.mode.hasEstablishedHand)
        )
    }

    init() {
        let camera = CameraManager()
        let pipeline = HandTrackingPipeline()
        self.camera = camera
        self.pipeline = pipeline

        camera.onFrame = { frame in pipeline.submit(frame) }
        camera.onFrameDropped = { pipeline.recordCameraDrop() }
        camera.onStatusChange = { [weak self] status in
            guard let self else { return }
            Self.deliver { self.apply(status) }
        }
        pipeline.onResult = { [weak self] result in
            guard let self else { return }
            Self.deliver { self.apply(result) }
        }
        pipeline.onMetrics = { [weak self] metrics in
            guard let self else { return }
            Self.deliver { self.apply(metrics) }
        }
        pipeline.apply(settings)

        // Returning from System Settings (or any app) re-checks the permission immediately:
        // no restart, no polling needed for the grant itself.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccessibility(reason: .appActivated) }
        }
        logAccessibility(reason: .launch)
    }

    /// Checks/requests permission and starts the camera. The app stays usable without permission.
    func activate() async {
        cameras = CameraManager.availableCameras()
        permission = CameraPermissionManager.current
        if permission == .notDetermined {
            permission = await CameraPermissionManager.request()
        }
        guard permission == .authorized else {
            Log.permissions.error("Camera permission not granted")
            cameraStatus = .permissionRequired
            return
        }
        if selectedCameraID == nil || !cameras.contains(where: { $0.id == selectedCameraID }) {
            selectedCameraID = CameraManager.defaultCameraID()
        }
        start()
    }

    func start() {
        resetTracking()
        camera.start(cameraID: selectedCameraID)
    }

    func stop() {
        camera.stop()
    }

    /// Refreshes the camera list and restarts (after an error, a disconnection or a new permission).
    func retry() async {
        selectedCameraID = nil
        await activate()
    }

    func selectCamera(_ id: String?) {
        guard cameraStatus == .running || cameraStatus == .ready else { return }
        start()
    }

    func openCameraSettings() {
        CameraPermissionManager.openSystemSettings()
    }

    // MARK: Cursor control

    func setCursorEnabled(_ enabled: Bool) {
        cursorEnabled = enabled
        if enabled {
            cursorPaused = false
            refreshAccessibility(reason: .userAction)
        }
        syncCursorControl()
    }

    func toggleCursorPause() {
        guard cursorEnabled else { return }
        cursorPaused.toggle()
        syncCursorControl()
    }

    /// Explicit user action only. Shows the system prompt at most once per session; afterwards
    /// the user is sent to System Settings instead.
    func requestAccessibility() {
        switch accessibility.requestAction() {
        case .none: break
        case .showSystemPrompt: AccessibilityPermissionManager.request()
        case .openSystemSettings: AccessibilityPermissionManager.openSystemSettings()
        }
        refreshAccessibility(reason: .userAction)
    }

    /// "Comprobar de nuevo": asks the system again right now.
    func recheckAccessibility() {
        refreshAccessibility(reason: .userAction)
    }

    func openAccessibilitySettings() {
        AccessibilityPermissionManager.openSystemSettings()
    }

    func updateSettings(_ newSettings: AirTrackSettings) {
        settings = newSettings.sanitized
        pipeline.apply(settings)
    }

    /// Re-checks the permission. Launch, activation and user actions always ask the system;
    /// the periodic check (revocation while running) at most once per second.
    private func refreshAccessibility(reason: AccessibilityRefreshReason) {
        let changed = accessibility.refresh(reason: reason, at: ProcessInfo.processInfo.systemUptime) {
            AccessibilityPermissionManager.isGranted
        }
        if reason != .periodic || changed {
            accessibilityDiagnostics = AccessibilityDiagnostics.current()
            logAccessibility(reason: reason)
        }
        if changed { syncCursorControl() }
    }

    /// Bundle ID, signature kind and both TCC answers are public; the executable path (it
    /// contains the user name) is private in the unified log. The panel shows it with "~".
    private func logAccessibility(reason: AccessibilityRefreshReason) {
        let d = accessibilityDiagnostics
        let state = accessibilityGranted ? "granted" : "missing"
        Log.permissions.info("Accessibility \(reason.rawValue, privacy: .public): \(state, privacy: .public) [AX trusted \(d.processTrusted, privacy: .public), post events \(d.canPostEvents, privacy: .public)] bundle \(d.bundleIdentifier, privacy: .public), signature \(d.signatureLabel, privacy: .public), executable \(d.executablePath, privacy: .private)")
    }

    /// The pipeline may move the cursor only when every condition holds. Any failure (camera
    /// stopped, paused, disabled, permission missing) turns it off immediately.
    private func syncCursorControl() {
        let allowed = cursorEnabled && !cursorPaused && accessibilityGranted && cameraStatus == .running
        pipeline.setCursorControl(allowed: allowed)
        if !allowed { cursor = nil }
    }

    private func apply(_ status: CameraStatus) {
        cameraStatus = status
        if status != .running {
            hands = []
            pointer = .lost(at: 0)
            candidateCount = 0
            rejections = []
        }
        syncCursorControl()
    }

    private func apply(_ newMetrics: TrackingMetrics) {
        metrics = newMetrics
        if cursorEnabled { refreshAccessibility(reason: .periodic) }
    }

    private func apply(_ result: TrackingResult) {
        guard cameraStatus == .running else { return }
        hands = result.hands
        candidateCount = result.candidateCount
        rejections = result.rejections
        cursor = result.cursor
        if pointer.mode == .holding, result.pointer.mode.providesPointer { bridgedGaps += 1 }
        if pointer.mode != .lost, result.pointer.mode == .lost { pointerLosses += 1 }
        pointer = result.pointer
        if result.imageAspectRatio.isFinite, result.imageAspectRatio > 0 { imageAspectRatio = result.imageAspectRatio }
        if !result.hands.isEmpty { hasSeenHand = true }
    }

    private func resetTracking() {
        hands = []
        candidateCount = 0
        rejections = []
        hasSeenHand = false
        cursor = nil
        pointer = .lost(at: 0)
        bridgedGaps = 0
        pointerLosses = 0
        metrics = TrackingMetrics()
        pipeline.reset()
    }

    /// Hops to the main actor preserving arrival order (unlike independent Tasks).
    nonisolated private static func deliver(_ work: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated(work)
        }
    }
}
