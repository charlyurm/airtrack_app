import XCTest
@testable import AirTrackCore

/// PHASE 3B event safety invariants, over random but reproducible interaction sequences and
/// over the pure controllers:
/// - mouseDown count ≤ 1 active drag; mouseUp count == mouseDown count
/// - no mouseUp without an active drag; no click while the button is down
/// - no click after drag commitment; no click after tracking loss
/// - no drag without a confirmed pinch; no stuck button after shutdown (cancel)
final class ClickDragSafetyTests: XCTestCase {
    private let poses: [(FingerSet, TestPoses.Thumb)] = [
        (TestPoses.pointing, .pinching), (TestPoses.pointing, .pinching), (TestPoses.pointing, .extended),
        (TestPoses.pointing, .folded), (TestPoses.twoFingers, .folded), (TestPoses.fourFingers, .extended),
        (TestPoses.twoFingers, .touchingMiddle),
    ]

    func testRandomInteractionNeverBreaksTheButtonInvariants() {
        var totals = (clicks: 0, drags: 0)
        for seed in UInt64(1)...16 {
            var generator = SeededGenerator(seed: seed)
            var d = HandDriver()
            var ledger = ButtonLedger()
            var draggedInThisPinch = false
            var violations: [String] = []

            for segment in 0..<80 {
                let (fingers, thumb) = poses[Int.random(in: 0..<poses.count, using: &generator)]
                let count = Int.random(in: 1...8, using: &generator)
                let move = Point2D(x: Double.random(in: -0.012...0.012, using: &generator),
                                   y: Double.random(in: -0.012...0.012, using: &generator))
                let roll = Int.random(in: 0..<24, using: &generator)
                let mode: PointerTrackingMode = switch roll {
                case 0: .lost
                case 1, 2: .holding
                case 3: .partial
                default: .full
                }
                if roll == 4 { d.outputs = d.outputs.isEmpty ? .all : [] }
                if roll == 5 {
                    // Pause / permission / camera / shutdown.
                    let closing = d.engine.cancel()
                    if closing.contains(.leftClick) || closing.contains(.beginDrag) { violations.append("cancel emitted \(closing)") }
                    ledger.record(closing, at: "cancel seed \(seed) segment \(segment)")
                    draggedInThisPinch = false
                }
                for _ in 0..<count {
                    let silent = d.outputs.isEmpty
                    d.center = Rect2D(x: 0.3, y: 0.3, width: 0.4, height: 0.4).clamp(d.center)
                    let f = d.step(fingers, thumb, move: move, mode: mode)
                    let label = "seed \(seed) t=\(f.timestamp)"
                    if f.clicks > 0 {
                        if f.availability != .available { violations.append("click without fresh FULL tracking \(label)") }
                        if draggedInThisPinch { violations.append("click after a drag commit \(label)") }
                        if f.clicks > 1 { violations.append("several clicks in one frame \(label)") }
                    }
                    if f.beginsDrag {
                        if f.intent != .pinch || f.availability != .available { violations.append("drag without a confirmed pinch \(label)") }
                        draggedInThisPinch = true
                    }
                    // Silenced output may only close things (mouseUp, scroll ended), never start them.
                    if silent, f.actions.contains(.leftClick) || f.actions.contains(.beginDrag) {
                        violations.append("button output while silenced \(label)")
                    }
                    ledger.record(f.actions, at: label)
                    if ledger.isDown, f.intent != .pinch { violations.append("button held without a pinch owner \(label)") }
                    if f.intent == nil { draggedInThisPinch = false }
                }
            }
            // Shutdown: nothing may stay pressed.
            ledger.record(d.engine.cancel(), at: "shutdown seed \(seed)")
            XCTAssertEqual(violations + ledger.violations, [], "seed \(seed)")
            XCTAssertEqual(ledger.downs, ledger.ups, "every mouseDown has its mouseUp (seed \(seed))")
            XCTAssertFalse(ledger.isDown)
            XCTAssertFalse(d.engine.pinchIntent.isButtonDown)
            totals.clicks += ledger.clicks
            totals.drags += ledger.downs
        }
        // The sequences really exercise both paths.
        XCTAssertGreaterThan(totals.clicks, 0)
        XCTAssertGreaterThan(totals.drags, 0)
    }

    func testClickAndDragAreExclusivePerPinch() {
        // Same pinch, every movement amount: exactly one of {click, drag, nothing}, never both.
        for steps in 0..<12 {
            var d = HandDriver()
            let frames = d.pinch(count: 2) + d.pinch(count: steps, move: Point2D(x: 0.004, y: 0.003)) + d.open(count: 2)
            let actions = frames.buttonActions
            XCTAssertTrue(actions == [.leftClick] || actions == [.beginDrag, .endDrag], "\(steps) steps: \(actions)")
        }
    }

    // MARK: PinchIntentController

    private let pointer = PointerObservation(mode: .full, indexTip: Point2D(x: 0.5, y: 0.5), indexConfidence: 0.9, timestamp: 0)

    func testControllerEmitsDragPairOnlyWhenLive() {
        var live = PinchIntentController()
        live.begin(at: 0, features: nil, pointer: pointer, live: true)
        XCTAssertEqual(live.update(step: MotionVector(dx: 0.2, dy: 0), held: true, availability: .available, now: 0.1), [.beginDrag])
        XCTAssertEqual(live.update(step: MotionVector(dx: 0.2, dy: 0), held: true, availability: .available, now: 0.2), [], "one mouseDown")
        XCTAssertEqual(live.release(reason: .gestureEnded, availability: .available, now: 0.3), [.endDrag])
        XCTAssertEqual(live.release(reason: .gestureEnded, availability: .available, now: 0.4), [], "one mouseUp")

        var shadow = PinchIntentController()
        shadow.begin(at: 0, features: nil, pointer: pointer, live: false)
        XCTAssertEqual(shadow.update(step: MotionVector(dx: 0.2, dy: 0), held: true, availability: .available, now: 0.1), [])
        XCTAssertEqual(shadow.phase, .dragging)
        XCTAssertEqual(shadow.release(reason: .gestureEnded, availability: .available, now: 0.3), [])
    }

    func testControllerNeverCommitsADragWithoutFreshSupportedEvidence() {
        let cases: [(held: Bool, availability: FeatureAvailability)] = [(false, .available), (true, .limited), (false, .gap)]
        for (held, availability) in cases {
            var c = PinchIntentController()
            c.begin(at: 0, features: nil, pointer: pointer, live: true)
            XCTAssertEqual(c.update(step: MotionVector(dx: 0.5, dy: 0), held: held, availability: availability, now: 0.1), [])
            XCTAssertEqual(c.phase, .pending)
        }
    }

    func testControllerClicksOnlyOnACleanFreshRelease() {
        let cases: [(ReleaseReason, FeatureAvailability, Bool)] = [
            (.gestureEnded, .available, true),
            (.gestureEnded, .limited, false),
            (.recognitionTimeout, .available, false),
            (.trackingLost, .lost, false),
            (.cancelled, .available, false),
        ]
        for (reason, availability, clicks) in cases {
            var c = PinchIntentController()
            c.begin(at: 0, features: nil, pointer: pointer, live: true)
            XCTAssertEqual(c.release(reason: reason, availability: availability, now: 0.2), clicks ? [.leftClick] : [], "\(reason) \(availability)")
            XCTAssertNil(c.session)
        }
    }

    func testControllerCancelAndSilenceOweAMouseUpOnlyWhenPressed() {
        var pending = PinchIntentController()
        pending.begin(at: 0, features: nil, pointer: pointer, live: true)
        XCTAssertEqual(pending.silence(), [])
        XCTAssertEqual(pending.cancel(), [])

        var pressed = PinchIntentController()
        pressed.begin(at: 0, features: nil, pointer: pointer, live: true)
        _ = pressed.update(step: MotionVector(dx: 0.3, dy: 0), held: true, availability: .available, now: 0.1)
        XCTAssertEqual(pressed.silence(), [.endDrag])
        XCTAssertEqual(pressed.silence(), [])
        XCTAssertEqual(pressed.cancel(), [], "already released by the silence")

        var restarted = PinchIntentController()
        restarted.begin(at: 0, features: nil, pointer: pointer, live: true)
        _ = restarted.update(step: MotionVector(dx: 0.3, dy: 0), held: true, availability: .available, now: 0.1)
        XCTAssertEqual(restarted.begin(at: 0.2, features: nil, pointer: pointer, live: true), [.endDrag],
                       "a pressed session is never forgotten")
        XCTAssertFalse(restarted.isButtonDown)
    }

    // MARK: DragController (anchor + ledger)

    func testDragAnchorIsFixedAndStartsWithoutAJump() {
        var drag = DragController()
        XCTAssertTrue(drag.press(at: Point2D(x: 0.4, y: 0.4)))
        XCTAssertPointEqual(drag.follow(index: Point2D(x: 0.6, y: 0.7)), Point2D(x: 0.4, y: 0.4), "first sample: no jump")
        XCTAssertPointEqual(drag.follow(index: Point2D(x: 0.65, y: 0.7)), Point2D(x: 0.45, y: 0.4))
        XCTAssertPointEqual(drag.follow(index: Point2D(x: 0.5, y: 0.8)), Point2D(x: 0.3, y: 0.5), "offset never recomputed")
        XCTAssertPointEqual(drag.offset, Point2D(x: -0.2, y: -0.3))
    }

    func testDragIsClampedToTheScreen() {
        var drag = DragController()
        XCTAssertTrue(drag.press(at: Point2D(x: 0.9, y: 0.1)))
        _ = drag.follow(index: Point2D(x: 0.5, y: 0.5))
        XCTAssertPointEqual(drag.follow(index: Point2D(x: 0.9, y: 0.2)), Point2D(x: 1, y: 0))
        XCTAssertPointEqual(drag.follow(index: Point2D(x: 0.55, y: 0.5)), Point2D(x: 0.95, y: 0.1), "back from the edge without drift")
    }

    func testDragLedgerNeverDoublesOrOrphansButtonEvents() {
        var drag = DragController()
        XCTAssertNil(drag.release(), "no mouseUp without a mouseDown")
        XCTAssertNil(drag.follow(index: Point2D(x: 0.5, y: 0.5)), "no drag movement without the button")
        XCTAssertTrue(drag.press(at: Point2D(x: 0.2, y: 0.3)))
        XCTAssertFalse(drag.press(at: Point2D(x: 0.8, y: 0.8)), "a second mouseDown is ignored")
        _ = drag.follow(index: Point2D(x: 0.5, y: 0.5))
        _ = drag.follow(index: Point2D(x: 0.55, y: 0.5))
        XCTAssertPointEqual(drag.release(), Point2D(x: 0.25, y: 0.3), "released where the drag is")
        XCTAssertNil(drag.release(), "idempotent")
        XCTAssertFalse(drag.isButtonDown)
    }

    func testDragIgnoresInvalidSamples() {
        var drag = DragController()
        XCTAssertFalse(drag.press(at: Point2D(x: .nan, y: 0.5)))
        XCTAssertTrue(drag.press(at: Point2D(x: 0.5, y: 0.5)))
        XCTAssertNil(drag.follow(index: Point2D(x: .infinity, y: 0.5)))
        XCTAssertNil(drag.offset, "an invalid sample never fixes the anchor")
        XCTAssertPointEqual(drag.release(), Point2D(x: 0.5, y: 0.5))
    }
}
