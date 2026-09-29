import XCTest
@testable import AirTrackCore

final class GestureEngineTests: XCTestCase {
    private func makeEngine(smoothing: Double = 0) -> GestureEngine {
        var settings = AirTrackSettings()
        settings.cursorSmoothing = smoothing
        return GestureEngine(settings: settings)
    }

    @discardableResult
    private func step(_ engine: inout GestureEngine, _ t: Double, ratio: Double, x: Double = 0.5, paused: Bool = false) -> GestureOutput {
        engine.process(TestHands.hand(at: t, indexTip: Point2D(x: x, y: 0.5), pinchRatio: ratio), isPaused: paused)
    }

    private func mouseDowns(_ actions: [InteractionAction]) -> [(Point2D, Int)] {
        actions.compactMap {
            if case let .mouseDown(at, count) = $0 { return (at, count) }
            return nil
        }
    }

    private func mouseUps(_ actions: [InteractionAction]) -> [(Point2D, Int)] {
        actions.compactMap {
            if case let .mouseUp(at, count) = $0 { return (at, count) }
            return nil
        }
    }

    func testPhysicalPinchThroughTheFullPipelineIsOneClick() {
        var engine = makeEngine()
        var actions: [InteractionAction] = []
        let ratios: [(Double, Double)] = [(0, 0.6), (0.033, 0.6), (0.066, 0.1), (0.1, 0.1), (0.133, 0.1), (0.166, 0.6), (0.2, 0.6), (0.233, 0.6)]
        for (t, ratio) in ratios {
            actions += step(&engine, t, ratio: ratio).actions
        }
        let downs = mouseDowns(actions)
        let ups = mouseUps(actions)
        XCTAssertEqual(downs.count, 1)
        XCTAssertEqual(ups.count, 1)
        XCTAssertEqual(downs.first?.1, 1)
        XCTAssertPointEqual(downs.first?.0, Point2D(x: 0.5, y: 0.5))
        XCTAssertPointEqual(ups.first?.0, Point2D(x: 0.5, y: 0.5))
    }

    func testPausedEngineEmitsNothing() {
        var engine = makeEngine()
        for i in 0..<30 {
            let ratio = i.isMultiple(of: 3) ? 0.1 : 0.6
            XCTAssertEqual(step(&engine, Double(i) / 30, ratio: ratio, x: Double(i) / 30, paused: true), .empty)
        }
    }

    func testPauseDuringDragReleasesOnceAndResumeRequiresOpenHand() {
        var engine = makeEngine()
        step(&engine, 0, ratio: 0.6)
        for t in [0.033, 0.066, 0.1, 0.2, 0.3, 0.4] { step(&engine, t, ratio: 0.1) }
        guard case .dragging = engine.phase else {
            return XCTFail("expected dragging, got \(engine.phase)")
        }

        let pause = step(&engine, 0.5, ratio: 0.1, paused: true)
        XCTAssertEqual(mouseUps(pause.actions).count, 1)
        XCTAssertEqual(pause.events, [.cancelled(.paused)])
        XCTAssertEqual(step(&engine, 0.533, ratio: 0.1, paused: true), .empty)

        // Resume with the hand still pinched: must not click.
        var resumed: [InteractionAction] = []
        for t in [0.6, 0.633, 0.666] { resumed += step(&engine, t, ratio: 0.1).actions }
        XCTAssertTrue(mouseDowns(resumed).isEmpty)
        XCTAssertEqual(engine.phase, .pointing)

        // Open, then pinch again: works normally.
        step(&engine, 0.7, ratio: 0.6)
        step(&engine, 0.733, ratio: 0.6)
        step(&engine, 0.766, ratio: 0.1)
        XCTAssertEqual(step(&engine, 0.8, ratio: 0.1).events, [.pinchStarted(clickCount: 1)])
    }

    func testHandThatAppearsPinchedNeverClicks() {
        var engine = makeEngine()
        var actions: [InteractionAction] = []
        for i in 0..<10 { actions += step(&engine, Double(i) / 30, ratio: 0.1).actions }
        for i in 10..<15 { actions += step(&engine, Double(i) / 30, ratio: 0.6).actions }
        XCTAssertTrue(mouseDowns(actions).isEmpty)
        XCTAssertTrue(mouseUps(actions).isEmpty)
    }

    func testTrackingLossStopsTheCursorAndResetsSmoothing() {
        var engine = makeEngine(smoothing: 0.5)
        for i in 0..<5 { step(&engine, Double(i) / 30, ratio: 0.6, x: 0.3) }

        for i in 5..<15 {
            let out = engine.process(.untracked(at: Double(i) / 30), isPaused: false)
            XCTAssertEqual(out.actions, [], "no cursor events while the hand is missing")
        }
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertNil(engine.smoother.current)

        // Reacquired elsewhere: jump straight there, no smoothed sweep from the old position.
        let back = step(&engine, 0.6, ratio: 0.6, x: 0.7)
        guard case let .moveCursor(to)? = back.actions.first else {
            return XCTFail("expected a cursor move, got \(back.actions)")
        }
        let area = CursorMapper.defaultActiveArea
        XCTAssertPointEqual(to, Point2D(x: (0.3 - area.minX) / area.width, y: 0.5))
    }

    func testDefaultSettingsDoNotUseTheFinderShortcut() {
        let shortcut = AirTrackSettings.default.emergencyToggleShortcut
        XCTAssertNotEqual(shortcut.modifiers, [.command, .shift])
        XCTAssertEqual(shortcut.displayString, "⌃⌥⌘A")
    }

    func testSettingsAreSanitized() {
        var settings = AirTrackSettings()
        settings.cursorSmoothing = 5
        settings.cursorSensitivity = -1
        settings.pinchThreshold = 0.5
        settings.pinchReleaseThreshold = 0.4
        settings.doubleClickInterval = 10
        settings.activeArea = Rect2D(x: 0, y: 0, width: -1, height: 1)

        let s = settings.sanitized
        XCTAssertEqual(s.cursorSmoothing, CursorSmoother.smoothingRange.upperBound)
        XCTAssertEqual(s.cursorSensitivity, CursorMapper.sensitivityRange.lowerBound)
        XCTAssertGreaterThan(s.pinchReleaseThreshold, s.pinchThreshold)
        XCTAssertEqual(s.doubleClickInterval, AirTrackSettings.doubleClickIntervalRange.upperBound)
        XCTAssertEqual(s.activeArea, CursorMapper.defaultActiveArea)
    }

    func testSettingsRoundTripThroughCodable() throws {
        var settings = AirTrackSettings()
        settings.cursorSensitivity = 1.7
        settings.emergencyToggleShortcut = KeyboardShortcut(keyCode: 0x23, key: "P", modifiers: [.control, .option])
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(AirTrackSettings.self, from: data), settings)
    }
}
