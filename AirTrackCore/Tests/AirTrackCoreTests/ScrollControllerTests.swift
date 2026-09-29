import XCTest
@testable import AirTrackCore

/// PHASE 3A-2: scroll response, deadband, fractional accumulation and bounded inertia.
/// Hand speeds are in hand scales per second; deltas are content points (+ = content down).
final class ScrollControllerTests: XCTestCase {
    private let dt = 1.0 / 30

    /// Scrolls at a constant hand speed for `frames` frames; returns the sum of the deltas.
    private func scroll(_ c: inout ScrollController, speed: Double, frames: Int) -> Int {
        var total = c.begin(step: (dy: speed * dt, dt: dt)).delta
        for _ in 0..<frames { total += c.update(dy: speed * dt, dt: dt)?.delta ?? 0 }
        return total
    }

    // MARK: Deadband

    func testStillHandProducesNothing() {
        var c = ScrollController()
        XCTAssertEqual(c.begin(step: (dy: 0, dt: dt)).delta, 0)
        for _ in 0..<30 { XCTAssertNil(c.update(dy: 0, dt: dt)) }
    }

    func testTinyMovementInsideTheDeadbandProducesNothing() {
        var c = ScrollController()
        XCTAssertEqual(scroll(&c, speed: 0.1, frames: 30), 0)
        XCTAssertEqual(c.contentSpeed(forHandSpeed: 0.1), 0)
    }

    func testIntentionalSlowMovementScrolls() {
        var c = ScrollController()
        XCTAssertGreaterThan(scroll(&c, speed: 0.5, frames: 10), 0)
    }

    func testDeadbandIsSoftNoJumpAtTheThreshold() {
        let c = ScrollController()
        XCTAssertEqual(c.contentSpeed(forHandSpeed: 0.15), 0)
        XCTAssertLessThan(c.contentSpeed(forHandSpeed: 0.16), 5, "just above the deadband scrolls very slowly")
    }

    // MARK: Velocity response

    func testFasterMovementGivesLargerDeltas() {
        var totals: [Int] = []
        for speed in [0.5, 1.0, 2.2, 4.0] {
            var c = ScrollController()
            totals.append(scroll(&c, speed: speed, frames: 10))
        }
        XCTAssertEqual(totals, totals.sorted())
        XCTAssertEqual(Set(totals).count, totals.count, "strictly increasing: \(totals)")
        // Faster also scrolls more per unit of hand travel (gentle acceleration).
        XCTAssertGreaterThan(Double(totals[3]) / 4.0, Double(totals[0]) / 0.5)
    }

    func testDirectionFollowsTheHand() {
        var down = ScrollController()
        var up = ScrollController()
        XCTAssertGreaterThan(scroll(&down, speed: 2, frames: 5), 0, "hand down → content down")
        XCTAssertLessThan(scroll(&up, speed: -2, frames: 5), 0, "hand up → content up")
    }

    func testSpeedIsCapped() {
        let c = ScrollController()
        XCTAssertEqual(c.contentSpeed(forHandSpeed: 100), c.configuration.maximumSpeed)
        XCTAssertEqual(c.contentSpeed(forHandSpeed: .nan), 0)
    }

    func testSensitivityScalesTheResponse() {
        var normal = ScrollController()
        var double = ScrollController()
        double.sensitivity = 2
        let a = scroll(&normal, speed: 1, frames: 10)
        let b = scroll(&double, speed: 1, frames: 10)
        XCTAssertEqual(Double(b), Double(a) * 2, accuracy: 2)
    }

    // MARK: Decimal accumulation

    func testFractionalDeltasAreNeverLost() {
        var c = ScrollController()
        // ≈ 0.4 points per frame: nothing whole in one frame, but it must add up.
        let speed = 0.15 + 0.0474
        var emitted = c.begin(step: (dy: speed * dt, dt: dt)).delta
        var frames = 1
        for _ in 0..<29 {
            emitted += c.update(dy: speed * dt, dt: dt)?.delta ?? 0
            frames += 1
        }
        let exact = c.contentSpeed(forHandSpeed: speed) * dt * Double(frames)
        XCTAssertGreaterThan(emitted, 0, "slow scrolling eventually moves")
        XCTAssertEqual(Double(emitted), exact.rounded(.towardZero), accuracy: 1, "only the last fraction may be pending")
    }

    // MARK: Phases

    func testBeginChangedEnded() {
        var c = ScrollController()
        XCTAssertEqual(c.begin(step: (dy: 2 * dt, dt: dt)).phase, .began)
        XCTAssertEqual(c.update(dy: 2 * dt, dt: dt)?.phase, .changed)
        XCTAssertEqual(c.end(allowMomentum: false, at: 1), [ScrollAction(delta: 0, phase: .ended)])
        XCTAssertEqual(c.state, .idle)
        XCTAssertEqual(c.end(allowMomentum: true, at: 2), [], "nothing to end twice")
    }

    // MARK: Inertia

    private func momentum(_ c: inout ScrollController, from start: TimeInterval = 0, step: TimeInterval = 1.0 / 30) -> [ScrollAction] {
        var out: [ScrollAction] = []
        var t = start
        for _ in 0..<600 {
            t += step
            if let a = c.tick(at: t) { out.append(a) }
            if c.state == .idle { break }
        }
        return out
    }

    func testStoppingWhileHoldingThePoseStopsWithoutInertia() {
        var c = ScrollController()
        _ = scroll(&c, speed: 2.2, frames: 5)
        for _ in 0..<8 { _ = c.update(dy: 0, dt: dt) }
        XCTAssertEqual(c.pointsPerSecond, 0)
        _ = c.end(allowMomentum: true, at: 0)
        XCTAssertEqual(c.state, .idle, "the hand had stopped: no momentum")
    }

    func testInertiaAfterAFastReleaseDecaysAndStops() {
        var c = ScrollController()
        _ = scroll(&c, speed: 2.2, frames: 5)
        _ = c.end(allowMomentum: true, at: 0)
        XCTAssertEqual(c.state, .momentum)
        let steps = momentum(&c)
        XCTAssertEqual(steps.first?.momentum, .began)
        XCTAssertEqual(steps.last, ScrollAction(delta: 0, phase: nil, momentum: .ended))
        let deltas = steps.dropLast().map(\.delta)
        XCTAssertTrue(deltas.allSatisfy { $0 >= 0 }, "same direction")
        // Decays; whole points may wobble by 1 because the fraction is carried between steps.
        XCTAssertTrue(zip(deltas, deltas.dropFirst()).allSatisfy { $1 <= $0 + 1 }, "decays: \(deltas)")
        XCTAssertGreaterThan(deltas.first ?? 0, (deltas.last ?? 0) * 5)
        XCTAssertEqual(c.state, .idle)
        XCTAssertNil(c.tick(at: 100), "nothing after the end")
    }

    func testInertiaIsBoundedInDurationSpeedAndDistance() {
        var c = ScrollController()
        _ = scroll(&c, speed: 50, frames: 5) // absurdly fast hand
        XCTAssertLessThanOrEqual(abs(c.pointsPerSecond), c.configuration.maximumSpeed)
        _ = c.end(allowMomentum: true, at: 0)
        var t = 0.0
        var total = 0
        var ticks = 0
        while c.state == .momentum, ticks < 1000 {
            t += dt
            ticks += 1
            total += c.tick(at: t)?.delta ?? 0
        }
        XCTAssertLessThanOrEqual(t, c.configuration.inertiaMaximumDuration + dt + 1e-9)
        XCTAssertLessThanOrEqual(Double(total), c.configuration.inertiaDistanceBound)
    }

    func testInertiaIsFrameRateIndependentAndDeterministic() {
        func total(step: TimeInterval) -> Int {
            var c = ScrollController()
            _ = scroll(&c, speed: 2.2, frames: 5)
            _ = c.end(allowMomentum: true, at: 0)
            return momentum(&c, step: step).map(\.delta).reduce(0, +)
        }
        XCTAssertEqual(total(step: 1.0 / 30), total(step: 1.0 / 30))
        XCTAssertEqual(Double(total(step: 1.0 / 30)), Double(total(step: 1.0 / 60)), accuracy: 3)
    }

    func testNoInertiaWhenNotAllowedOrTooSlow() {
        var lost = ScrollController()
        _ = scroll(&lost, speed: 2.2, frames: 5)
        _ = lost.end(allowMomentum: false, at: 0)
        XCTAssertEqual(lost.state, .idle, "stale data (LOST) never starts inertia")

        var slow = ScrollController()
        _ = scroll(&slow, speed: 0.4, frames: 5)
        _ = slow.end(allowMomentum: true, at: 0)
        XCTAssertEqual(slow.state, .idle)
    }

    func testCancellingInertiaClosesItsPhase() {
        var c = ScrollController()
        _ = scroll(&c, speed: 2.2, frames: 5)
        _ = c.end(allowMomentum: true, at: 0)
        _ = c.tick(at: dt)
        XCTAssertEqual(c.cancelMomentum(), [ScrollAction(delta: 0, phase: nil, momentum: .ended)])
        XCTAssertEqual(c.state, .idle)
        XCTAssertEqual(c.cancelMomentum(), [])
    }

    func testCancelClosesWhateverIsOpen() {
        var idle = ScrollController()
        XCTAssertEqual(idle.cancel(), [])
        var scrolling = ScrollController()
        _ = scrolling.begin(step: (dy: 2 * dt, dt: dt))
        XCTAssertEqual(scrolling.cancel(), [ScrollAction(delta: 0, phase: .ended)])
        XCTAssertNil(scrolling.update(dy: 2 * dt, dt: dt), "no stale scroll after a cancel")
    }

    func testSensitivityIsSanitizedInSettings() {
        var s = AirTrackSettings()
        s.scrollSensitivity = 100
        XCTAssertEqual(s.sanitized.scrollSensitivity, AirTrackSettings.scrollSensitivityRange.upperBound)
        s.scrollSensitivity = .nan
        XCTAssertEqual(s.sanitized.scrollSensitivity, AirTrackSettings.default.scrollSensitivity)
        XCTAssertTrue(AirTrackSettings.default.scrollGesturesEnabled)
        XCTAssertFalse(AirTrackSettings.default.scrollDirectionInverted)
    }
}
