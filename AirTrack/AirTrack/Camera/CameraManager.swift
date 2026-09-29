import AVFoundation
import CoreMedia

struct CameraDevice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

enum CameraError: LocalizedError {
    case noCameraAvailable
    case cameraNotFound
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .noCameraAvailable: "No hay ninguna cámara disponible."
        case .cameraNotFound: "La cámara seleccionada ya no está disponible."
        case .cannotAddInput: "No se pudo conectar la cámara a la sesión de captura."
        case .cannotAddOutput: "No se pudo configurar la salida de video."
        }
    }
}

/// Owns the AVCaptureSession. Contains no tracking, gesture or cursor logic.
///
/// Threading (see Documentation/ARCHITECTURE.md):
/// - `sessionQueue` (serial): every session configuration change, start and stop.
/// - `videoQueue` (serial): sample buffer delivery → `onFrame`.
/// - Callbacks fire on those queues, never on the main thread; set them before `start`.
/// @unchecked Sendable: all mutable state is confined to `sessionQueue`.
final class CameraManager: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()

    var onStatusChange: (@Sendable (CameraStatus) -> Void)?
    var onFrame: (@Sendable (CameraFrame) -> Void)?
    var onFrameDropped: (@Sendable () -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.airtrack.camera.session")
    private let videoQueue = DispatchQueue(label: "com.airtrack.camera.video", qos: .userInteractive)
    private let videoOutput = AVCaptureVideoDataOutput()

    // sessionQueue only
    private var currentInput: AVCaptureDeviceInput?
    private var isOutputConfigured = false
    private var deviceObservers: [NSObjectProtocol] = []
    private var sessionObserver: NSObjectProtocol?

    deinit {
        for observer in deviceObservers { NotificationCenter.default.removeObserver(observer) }
        if let sessionObserver { NotificationCenter.default.removeObserver(sessionObserver) }
    }

    // MARK: Discovery

    static func availableCameras() -> [CameraDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        .devices
        .map { CameraDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    static func defaultCameraID() -> String? {
        AVCaptureDevice.default(for: .video)?.uniqueID ?? availableCameras().first?.id
    }

    // MARK: Control

    /// Configures the session for `cameraID` (or the system default) and starts it.
    /// Safe to call again to switch cameras or to retry after an error/disconnection.
    func start(cameraID: String?) {
        sessionQueue.async { [self] in
            guard CameraPermissionManager.current == .authorized else {
                report(.permissionRequired)
                return
            }
            do {
                try configure(cameraID: cameraID)
                report(.ready)
                if !session.isRunning {
                    session.startRunning() // blocking: must stay off the main thread
                }
                if session.isRunning {
                    Log.camera.info("Capture session started")
                    report(.running)
                } else {
                    report(.error("La sesión de captura no arrancó."))
                }
            } catch {
                Log.camera.error("Camera configuration failed: \(error.localizedDescription, privacy: .public)")
                report(.error(error.localizedDescription))
            }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning {
                session.stopRunning()
                Log.camera.info("Capture session stopped")
            }
            report(.stopped)
        }
    }

    // MARK: Configuration (sessionQueue)

    private func configure(cameraID: String?) throws {
        let device = try selectDevice(id: cameraID)
        if let currentInput, currentInput.device.uniqueID == device.uniqueID, isOutputConfigured {
            return
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        } else {
            session.sessionPreset = .high
        }

        if let currentInput {
            session.removeInput(currentInput)
            self.currentInput = nil
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)
        currentInput = input

        if !isOutputConfigured {
            videoOutput.alwaysDiscardsLateVideoFrames = true // prefer dropping over queueing latency
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            ]
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
            guard session.canAddOutput(videoOutput) else { throw CameraError.cannotAddOutput }
            session.addOutput(videoOutput)
            isOutputConfigured = true
        }

        // Frames delivered to Vision are NEVER mirrored: HandState is defined on the raw image.
        // Mirroring is a preview-only concern (CameraPreviewView).
        if let connection = videoOutput.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }

        observe(device)
        Log.camera.info("Camera selected: \(device.localizedName, privacy: .public)")
    }

    private func selectDevice(id: String?) throws -> AVCaptureDevice {
        if let id {
            guard let device = AVCaptureDevice(uniqueID: id), device.isConnected else {
                throw CameraError.cameraNotFound
            }
            return device
        }
        guard let device = AVCaptureDevice.default(for: .video) else { throw CameraError.noCameraAvailable }
        return device
    }

    private func observe(_ device: AVCaptureDevice) {
        for observer in deviceObservers { NotificationCenter.default.removeObserver(observer) }
        deviceObservers = [
            NotificationCenter.default.addObserver(
                forName: AVCaptureDevice.wasDisconnectedNotification, object: device, queue: nil
            ) { [weak self] _ in
                guard let self else { return }
                self.sessionQueue.async { self.handleDisconnection() }
            },
        ]

        if sessionObserver == nil {
            sessionObserver = NotificationCenter.default.addObserver(
                forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil
            ) { [weak self] note in
                let message = (note.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription
                    ?? "Error de la sesión de captura."
                guard let self else { return }
                self.sessionQueue.async { self.handleRuntimeError(message) }
            }
        }
    }

    private func handleDisconnection() {
        Log.camera.error("Camera disconnected")
        if session.isRunning { session.stopRunning() }
        if let currentInput {
            session.beginConfiguration()
            session.removeInput(currentInput)
            session.commitConfiguration()
            self.currentInput = nil
        }
        report(.disconnected)
    }

    private func handleRuntimeError(_ message: String) {
        // A runtime error right after an unplug is the disconnection, not a new failure.
        guard currentInput?.device.isConnected ?? false else {
            handleDisconnection()
            return
        }
        Log.camera.error("Capture session runtime error: \(message, privacy: .public)")
        report(.error(message))
    }

    private func report(_ status: CameraStatus) {
        onStatusChange?(status)
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let frame = CameraFrame(
            pixelBuffer: pixelBuffer,
            timestamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds,
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
        onFrame?(frame)
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        onFrameDropped?()
    }
}
