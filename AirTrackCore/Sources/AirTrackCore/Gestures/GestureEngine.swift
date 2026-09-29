import Foundation

/// Per-frame pipeline: HandState → cursor mapping → smoothing → pinch → state machine.
///
/// Pure and deterministic: the macOS layer feeds it one HandState per camera frame and
/// posts the returned actions. Scroll (PHASE 5) is not part of it yet.
public struct GestureEngine: Sendable {
    public private(set) var settings: AirTrackSettings
    public private(set) var cursorMapper: CursorMapper
    public private(set) var smoother: CursorSmoother
    public private(set) var pinchRecognizer: PinchRecognizer
    public private(set) var stateMachine: GestureStateMachine
    public private(set) var lastPinchReading: PinchReading?
    public private(set) var isPaused = false

    public init(settings: AirTrackSettings = .default) {
        let s = settings.sanitized
        self.settings = s
        self.cursorMapper = s.cursorMapper
        self.smoother = CursorSmoother(smoothing: s.cursorSmoothing)
        self.pinchRecognizer = PinchRecognizer(configuration: s.pinchConfiguration)
        self.stateMachine = GestureStateMachine(configuration: s.gestureConfiguration)
    }

    public var phase: GesturePhase { stateMachine.phase }

    /// Applies new settings without dropping an in-progress gesture.
    public mutating func apply(_ settings: AirTrackSettings) {
        let s = settings.sanitized
        self.settings = s
        cursorMapper = s.cursorMapper
        smoother.smoothing = s.cursorSmoothing
        pinchRecognizer.configuration = s.pinchConfiguration
        stateMachine.configuration = s.gestureConfiguration
    }

    public mutating func process(_ hand: HandState, isPaused paused: Bool) -> GestureOutput {
        if paused {
            guard !isPaused else { return .empty }
            isPaused = true
            let output = stateMachine.update(.paused(timestamp: hand.timestamp))
            resetTracking()
            return output
        }
        isPaused = false

        guard let tip = hand.position(of: .indexTip, minimumConfidence: settings.minimumLandmarkConfidence),
              let mapped = cursorMapper.map(tip) else {
            let output = stateMachine.update(.trackingLost(timestamp: hand.timestamp))
            if stateMachine.phase == .idle { resetTracking() }
            return output
        }

        let finger = smoother.smooth(mapped)
        let reading = pinchRecognizer.update(with: hand)
        lastPinchReading = reading

        // The recognizer reports "not pinched" during its start-confirmation frames even for
        // a closed hand, so re-arming needs positive evidence of an open hand.
        var isPinched = reading.isPinched
        if stateMachine.requiresOpenHandBeforePinch {
            let releaseRatio = pinchRecognizer.configuration.sanitized.releaseRatio
            let clearlyOpen = reading.ratio.map { $0 > releaseRatio } ?? false
            if !clearlyOpen { isPinched = true }
        }
        return stateMachine.update(.frame(timestamp: hand.timestamp, finger: finger, isPinched: isPinched))
    }

    private mutating func resetTracking() {
        smoother.reset()
        pinchRecognizer.reset()
        lastPinchReading = nil
    }
}
