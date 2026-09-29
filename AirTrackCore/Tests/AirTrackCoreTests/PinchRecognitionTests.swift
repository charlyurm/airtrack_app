import XCTest
@testable import AirTrackCore

/// PHASE 3B: pinch detection — enter / exit with hysteresis, noise, confidence, hand size,
/// orientation, partial views and uncertainty. Candidates only: nothing here clicks by itself.
final class PinchRecognitionTests: XCTestCase {
    private let exit = PoseConfiguration().pinchExitDistance
    private let enter = PoseConfiguration().pinchEnterDistance

    func testThresholdsAreOrderedAndHandRelative() {
        XCTAssertLessThan(enter, exit, "hysteresis: enter < exit")
        let features = HandFeatureExtractor.features(of: TestPoses.hand(extended: TestPoses.pointing, thumb: .pinching))
        XCTAssertEqual(features?.thumbIndexDistance ?? -1, 0.126, accuracy: 0.002, "hand scales, not pixels")
        XCTAssertEqual(features?.pinchConfidence ?? -1, 0.9, accuracy: 1e-9)
    }

    func testPinchIsConfirmedAfterTwoStableFramesAndEmitsNothing() {
        var d = HandDriver()
        let frames = d.pinch(count: 3)
        XCTAssertNil(frames[0].intent, "one frame is only a candidate")
        XCTAssertEqual(frames[0].pinch.phase, .candidate)
        XCTAssertEqual(frames[1].intent, .pinch)
        XCTAssertEqual(frames[1].lifecycle, .confirmed)
        XCTAssertEqual(frames[1].pinch.phase, .pending)
        XCTAssertEqual(frames[2].lifecycle, .active)
        XCTAssertTrue(frames.allSatisfy { $0.actions.isEmpty }, "confirmation alone never clicks")
    }

    func testDistanceInsideTheBandNeverStartsAPinch() {
        var d = HandDriver()
        let frames = d.run(count: 12, thumbDistance: (enter + exit) / 2)
        XCTAssertTrue(frames.allSatisfy { $0.intent == nil && $0.actions.isEmpty })
    }

    func testHysteresisKeepsAHeldPinchInsideTheBand() {
        var d = HandDriver()
        _ = d.pinch(count: 2)
        let band = d.run(count: 10, thumbDistance: (enter + exit) / 2)
        XCTAssertTrue(band.allSatisfy { $0.intent == .pinch && $0.maintenance == .supported && $0.actions.isEmpty })
        let beyond = d.run(count: 2, thumbDistance: exit + 0.05)
        XCTAssertEqual(beyond.last?.released, .gestureEnded, "beyond the exit distance the pinch ends")
    }

    func testOneNoisyOpenFrameDoesNotRelease() {
        var d = HandDriver()
        _ = d.pinch(count: 3)
        let blip = d.open(count: 1)[0]
        XCTAssertEqual(blip.intent, .pinch)
        XCTAssertEqual(blip.lifecycle, .suspended)
        XCTAssertTrue(blip.actions.isEmpty, "no click from one open frame")
        let back = d.pinch(count: 2)
        XCTAssertTrue(back.allSatisfy { $0.intent == .pinch && $0.lifecycle == .active })
        let release = d.open(count: 2)
        XCTAssertEqual(release.map(\.clicks), [0, 1], "the real release clicks once, on its second frame")
    }

    func testFlickeringPinchNeverConfirmsOrClicks() {
        var d = HandDriver()
        var frames: [InteractionFrame] = []
        for i in 0..<30 { frames.append(i.isMultiple(of: 2) ? d.pinch(count: 1)[0] : d.open(count: 1)[0]) }
        XCTAssertTrue(frames.allSatisfy { $0.intent == nil && $0.actions.isEmpty })
    }

    func testLowConfidenceTipsNeverStartAPinch() {
        var d = HandDriver()
        d.jointConfidence = 0.45 // measurable (≥ 0.3), but below the 0.5 needed to start
        let frames = d.pinch(count: 10) + d.open(count: 3)
        XCTAssertTrue(frames.allSatisfy { $0.intent == nil && $0.actions.isEmpty })
    }

    func testDifferentHandSizesBehaveTheSame() {
        for scale in [0.6, 1.0, 1.6] {
            var d = HandDriver()
            d.scale = scale
            let frames = d.pinch(count: 3) + d.open(count: 2)
            XCTAssertEqual(frames.buttonActions, [.leftClick], "scale \(scale)")
            XCTAssertEqual(frames[1].intent, .pinch, "scale \(scale)")
        }
    }

    func testDifferentOrientationsBehaveTheSame() {
        for rotation in [-0.6, -0.3, 0, 0.3, 0.6] {
            var d = HandDriver()
            d.rotation = rotation
            let frames = d.pinch(count: 3) + d.open(count: 2)
            XCTAssertEqual(frames.buttonActions, [.leftClick], "rotation \(rotation)")
        }
    }

    func testPartialViewNeverStartsAPinch() {
        var d = HandDriver()
        let frames = d.run(count: 10, mode: .partial, omit: [.wrist])
            + d.run(count: 10, mode: .indexContinuity)
        XCTAssertTrue(frames.allSatisfy { $0.intent == nil && $0.candidate == nil && $0.actions.isEmpty })
    }

    func testMissingTipIsUncertainAndHoldsTheConfirmedPinch() {
        var d = HandDriver()
        _ = d.pinch(count: 3)
        let occluded = d.run(count: 3, omit: [.thumbTip])
        XCTAssertTrue(occluded.allSatisfy { $0.intent == .pinch && $0.maintenance == .uncertain && $0.actions.isEmpty })
        XCTAssertTrue(d.pinch(count: 2).allSatisfy { $0.lifecycle == .active })
    }

    func testProlongedUncertaintyTimesOutWithoutAClick() {
        var d = HandDriver()
        _ = d.pinch(count: 3)
        let occluded = d.run(count: 12, omit: [.thumbTip])
        XCTAssertEqual(occluded.first { $0.released != nil }?.released, .recognitionTimeout)
        XCTAssertEqual(occluded.clickCount, 0, "a timeout is not a release: no click")
        XCTAssertEqual(occluded.last?.cursorPolicy, .follow)
    }

    func testFistIsNotAPinch() {
        var d = HandDriver()
        let frames = d.run([], .folded, count: 10) + d.run(TestPoses.pointing, .folded, count: 3)
        XCTAssertTrue(frames.allSatisfy { $0.intent == nil && $0.actions.isEmpty })
    }

    func testMaintenanceNeedsConsecutiveOpenFrames() {
        func features(_ distance: Double, at t: TimeInterval) -> HandFeatures {
            let hand = PinchGeometry.opening(TestPoses.hand(extended: TestPoses.pointing, thumb: .pinching, at: t), to: distance)
            return HandFeatureExtractor.features(of: hand)!
        }
        var history = FeatureHistory()
        let closed = features(0.12, at: 0)
        let open = features(0.8, at: 1.0 / 30)
        history.append(closed, pose: .pinch, mirrored: true)
        history.append(open, pose: .pinch, mirrored: true)
        XCTAssertEqual(PinchGestureRecognizer.maintenance(features: open, history: history, exitDistance: exit, releaseFrames: 2), .uncertain)
        let open2 = features(0.8, at: 2.0 / 30)
        history.append(open2, pose: .pointing, mirrored: true)
        XCTAssertEqual(PinchGestureRecognizer.maintenance(features: open2, history: history, exitDistance: exit, releaseFrames: 2), .contradicted)
        XCTAssertEqual(PinchGestureRecognizer.maintenance(features: closed, history: history, exitDistance: exit, releaseFrames: 2), .supported)
    }
}
