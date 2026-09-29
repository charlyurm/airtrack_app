import AirTrackCore
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
    /// Latest result from Vision (tracked or not). nil when the camera is not delivering.
    var hand: HandState?
    var metrics = TrackingMetrics()
    /// Whether a hand has been seen since the camera started (distinguishes LOST from NO HAND).
    private(set) var hasSeenHand = false

    let camera: CameraManager
    let pipeline: HandTrackingPipeline

    var session: AVCaptureSession { camera.session }

    var trackingLabel: String {
        guard cameraStatus == .running else { return "—" }
        if hand?.isTracked == true { return "HAND DETECTED" }
        return hasSeenHand ? "LOST" : "NO HAND"
    }

    var handCount: Int { hand?.isTracked == true ? 1 : 0 }

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
        pipeline.onHand = { [weak self] hand in
            guard let self else { return }
            Self.deliver { self.apply(hand) }
        }
        pipeline.onMetrics = { [weak self] metrics in
            guard let self else { return }
            Self.deliver { self.metrics = metrics }
        }
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

    private func apply(_ status: CameraStatus) {
        cameraStatus = status
        if status != .running {
            hand = nil
        }
    }

    private func apply(_ newHand: HandState) {
        guard cameraStatus == .running else { return }
        hand = newHand
        if newHand.isTracked { hasSeenHand = true }
    }

    private func resetTracking() {
        hand = nil
        hasSeenHand = false
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
