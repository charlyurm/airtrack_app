import XCTest
@testable import AirTrackCore

/// PHASE 2.1: velocity-aware, time-based cursor smoothing.
/// Positions are display-normalized (0…1); speeds in display-normalized units per second.
final class AdaptiveCursorSmootherTests: XCTestCase {
    private let dt = 1.0 / 30

    /// Feeds `points` at 30 fps starting at t0 and returns every output.
    private func run(_ s: inout AdaptiveCursorSmoother, _ points: [Point2D], from t0: TimeInterval = 0, dt: TimeInterval = 1.0 / 30) -> [Point2D] {
        points.enumerated().map { i, p in s.smooth(p, at: t0 + Double(i) * dt) }
    }

    /// Finger moving along x at `speed` from x = 0.2 for `frames` frames.
    private func ramp(speed: Double, frames: Int, from x0: Double = 0.2, dt: TimeInterval = 1.0 / 30) -> [Point2D] {
        (0..<frames).map { Point2D(x: x0 + speed * Double($0) * dt, y: 0.5) }
    }

    // MARK: Stationary and jitter

    func testStationaryInputStaysExactlyStill() {
        var s = AdaptiveCursorSmoother(restSmoothing: 0.6, speedResponse: 2)
        let still = Point2D(x: 0.4, y: 0.6)
        for output in run(&s, Array(repeating: still, count: 30)) {
            XCTAssertEqual(output, still)
        }
        XCTAssertEqual(s.speed, 0)
    }

    func testMicroJitterIsReducedAndKeepsNearlyFullSmoothing() {
        var s = AdaptiveCursorSmoother(restSmoothing: 0.6, speedResponse: 2)
        var generator = SeededGenerator(seed: 11)
        let center = Point2D(x: 0.5, y: 0.5)
        var inputEnergy = 0.0
        var outputEnergy = 0.0
        for i in 0..<120 {
            let noise = Point2D(x: Double.random(in: -0.002...0.002, using: &generator), y: Double.random(in: -0.002...0.002, using: &generator))
            let out = s.smooth(center + noise, at: Double(i) * dt)
            if i >= 10 {
                inputEnergy += noise.length * noise.length
                outputEnergy += (out - center).length * (out - center).length
                XCTAssertGreaterThan(s.lastWeight, 0.45, "jitter must not look like a fast movement")
            }
        }
        // RMS deviation from the true position drops (≈ half with these parameters).
        XCTAssertLessThan((outputEnergy / inputEnergy).squareRoot(), 0.7)
    }

    // MARK: Speed regimes

    func testWithoutSpeedResponseAt30FpsItIsExactlyThePhase2EMA() {
        var adaptive = AdaptiveCursorSmoother(restSmoothing: 0.35, speedResponse: 0)
        var ema = CursorSmoother(smoothing: 0.35)
        var generator = SeededGenerator(seed: 5)
        for i in 0..<60 {
            let p = Point2D(x: Double.random(in: 0...1, using: &generator), y: Double.random(in: 0...1, using: &generator))
            XCTAssertPointEqual(adaptive.smooth(p, at: Double(i) * dt), ema.smooth(p), accuracy: 1e-12)
        }
    }

    func testSmoothingDecreasesAsSpeedIncreases() {
        func steadyWeight(speed: Double) -> Double {
            var s = AdaptiveCursorSmoother(restSmoothing: 0.6, speedResponse: 2)
            _ = run(&s, ramp(speed: speed, frames: 20))
            return s.lastWeight
        }
        let slow = steadyWeight(speed: 0.05)
        let normal = steadyWeight(speed: 0.5)
        let fast = steadyWeight(speed: 2.5)
        XCTAssertGreaterThan(slow, 0.5, "slow: close to the rest smoothing (0.6)")
        XCTAssertLessThan(normal, slow)
        XCTAssertLessThan(fast, normal)
        XCTAssertLessThan(fast, 0.3, "fast: little smoothing")
    }

    func testSlowMovementIsFollowedSmoothly() {
        var s = AdaptiveCursorSmoother(restSmoothing: 0.6, speedResponse: 2)
        let outputs = run(&s, ramp(speed: 0.05, frames: 60))
        for (a, b) in zip(outputs, outputs.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.x, a.x, "monotonic: no back-and-forth")
        }
        // Steady-state lag ≈ speed · rest time constant (≈ 0.05 · 0.065 s), a few thousandths.
        XCTAssertLessThan(0.2 + 0.05 * 59 * dt - outputs.last!.x, 0.005)
    }

    func testFastMovementLagIsBoundedAndSmallerThanFixedSmoothing() {
        let speed = 2.5
        var adaptive = AdaptiveCursorSmoother(restSmoothing: 0.6, speedResponse: 2)
        var fixed = AdaptiveCursorSmoother(restSmoothing: 0.6, speedResponse: 0)
        let input = ramp(speed: speed, frames: 12)
        let a = run(&adaptive, input).last!
        let f = run(&fixed, input).last!
        let finger = input.last!.x
        let adaptiveLag = finger - a.x
        let fixedLag = finger - f.x
        XCTAssertLessThan(adaptiveLag, fixedLag / 3)
        // Bound: lag ≤ speed · tau(speed) ≤ restTimeConstant / speedResponse (+ one frame of estimate lag).
        XCTAssertLessThan(adaptiveLag, adaptive.restTimeConstant / 2 + speed * dt)
        XCTAssertGreaterThanOrEqual(adaptiveLag, 0, "never ahead of the finger")
    }

    func testAccelerationReducesSmoothingWithinAFewFrames() {
        var s = AdaptiveCursorSmoother(restSmoothing: 0.6, speedResponse: 2)
        _ = run(&s, Array(repeating: Point2D(x: 0.2, y: 0.5), count: 10))
        XCTAssertEqual(s.lastWeight, 0.6, accuracy: 1e-9)
        let fast = ramp(speed: 2.5, frames: 4, from: 0.2 + 2.5 * dt)
        _ = run(&s, fast, from: 10 * dt)
        XCTAssertLessThan(s.lastWeight, 0.3, "after ~4 frames of a fast movement smoothing has dropped")
    }

    func testDecelerationAndStopReturnToFullSmoothingWithoutOvershoot() {
        var s = AdaptiveCursorSmoother(restSmoothing: 0.6, speedResponse: 2)
        let fast = ramp(speed: 2.5, frames: 10)
        let outputs = run(&s, fast)
        let stop = fast.last!
        var previous = outputs.last!
        for i in 0..<45 {
            let out = s.smooth(stop, at: Double(10 + i) * dt)
            XCTAssertLessThanOrEqual(out.x, stop.x + 1e-12, "no overshoot past the stopped finger")
            XCTAssertGreaterThanOrEqual(out.x, previous.x - 1e-12, "no oscillation: monotonic approach")
            previous = out
        }
        XCTAssertEqual(previous.x, stop.x, accuracy: 1e-6, "settles on the finger")
        XCTAssertEqual(s.lastWeight, 0.6, accuracy: 0.02, "back to the rest smoothing")
    }

    func testDirectionReversalNeverOvershoots() {
        var s = AdaptiveCursorSmoother(restSmoothing: 0.5, speedResponse: 4)
        var inputs = ramp(speed: 2, frames: 8)
        let turn = inputs.last!.x
        inputs += (1...8).map { Point2D(x: turn - 2 * Double($0) * dt, y: 0.5) }
        var previousOutput: Point2D?
        for (i, p) in inputs.enumerated() {
            let out = s.smooth(p, at: Double(i) * dt)
            if let previousOutput {
                // Output lies between the previous output and the current input on each axis.
                XCTAssertLessThanOrEqual(out.x, max(previousOutput.x, p.x) + 1e-12)
                XCTAssertGreaterThanOrEqual(out.x, min(previousOutput.x, p.x) - 1e-12)
            }
            XCTAssertLessThanOrEqual(out.x, turn + 1e-12)
            previousOutput = out
        }
    }

    // MARK: Time base, determinism, robustness

    func testFrameRateIndependentWithoutSpeedResponse() {
        var at30 = AdaptiveCursorSmoother(restSmoothing: 0.7, speedResponse: 0)
        var at60 = AdaptiveCursorSmoother(restSmoothing: 0.7, speedResponse: 0)
        _ = at30.smooth(Point2D(x: 0, y: 0), at: 0)
        _ = at60.smooth(Point2D(x: 0, y: 0), at: 0)
        var a = Point2D.zero
        var b = Point2D.zero
        for i in 1...10 { a = at30.smooth(Point2D(x: 1, y: 1), at: Double(i) / 30) }
        for i in 1...20 { b = at60.smooth(Point2D(x: 1, y: 1), at: Double(i) / 60) }
        XCTAssertPointEqual(a, b, accuracy: 1e-12)
    }

    func testFrameRateChangesKeepTheResponseClose() {
        var at30 = AdaptiveCursorSmoother(restSmoothing: 0.6, speedResponse: 2)
        var at60 = AdaptiveCursorSmoother(restSmoothing: 0.6, speedResponse: 2)
        let a = run(&at30, ramp(speed: 1, frames: 16, dt: 1.0 / 30), dt: 1.0 / 30).last!
        let b = run(&at60, ramp(speed: 1, frames: 31, dt: 1.0 / 60), dt: 1.0 / 60).last!
        XCTAssertEqual(a.x, b.x, accuracy: 0.01)
    }

    func testSameInputsGiveSameOutputs() {
        var a = AdaptiveCursorSmoother(restSmoothing: 0.5, speedResponse: 3)
        var b = AdaptiveCursorSmoother(restSmoothing: 0.5, speedResponse: 3)
        var generator = SeededGenerator(seed: 21)
        for i in 0..<100 {
            let p = Point2D(x: Double.random(in: 0...1, using: &generator), y: Double.random(in: 0...1, using: &generator))
            XCTAssertEqual(a.smooth(p, at: Double(i) * dt), b.smooth(p, at: Double(i) * dt))
        }
    }

    func testOutputAlwaysStaysInsideTheInputRange() {
        var s = AdaptiveCursorSmoother(restSmoothing: 0.9, speedResponse: 8)
        var generator = SeededGenerator(seed: 8)
        for i in 0..<200 {
            let p = Point2D(x: Double.random(in: 0...1, using: &generator), y: Double.random(in: 0...1, using: &generator))
            // Irregular frame times, including long gaps.
            let t = Double(i) * dt + Double.random(in: 0...0.2, using: &generator)
            let out = s.smooth(p, at: t)
            XCTAssertTrue(out.isFinite)
            XCTAssertTrue((0...1).contains(out.x) && (0...1).contains(out.y))
        }
    }

    func testFirstSampleAndResetPassThrough() {
        var s = AdaptiveCursorSmoother(restSmoothing: 0.9, speedResponse: 2)
        XCTAssertEqual(s.smooth(Point2D(x: 0.1, y: 0.1), at: 0), Point2D(x: 0.1, y: 0.1))
        _ = s.smooth(Point2D(x: 0.9, y: 0.9), at: dt)
        s.reset()
        XCTAssertEqual(s.smooth(Point2D(x: 0.7, y: 0.3), at: 2 * dt), Point2D(x: 0.7, y: 0.3), "no stale position after reset")
        XCTAssertEqual(s.speed, 0)
    }

    func testDuplicateTimestampFallsBackToThePerFrameEMA() {
        var s = AdaptiveCursorSmoother(restSmoothing: 0.5, speedResponse: 8)
        _ = s.smooth(Point2D(x: 0, y: 0), at: 1)
        XCTAssertPointEqual(s.smooth(Point2D(x: 1, y: 1), at: 1), Point2D(x: 0.5, y: 0.5))
        XCTAssertPointEqual(s.smooth(Point2D(x: 1, y: 1), at: 0.5), Point2D(x: 0.75, y: 0.75), accuracy: 1e-9, "out-of-order time")
    }

    func testLongGapIsBoundedToOneStep() {
        var s = AdaptiveCursorSmoother(restSmoothing: 0.95, speedResponse: 0)
        _ = s.smooth(Point2D(x: 0, y: 0), at: 0)
        let out = s.smooth(Point2D(x: 1, y: 1), at: 10)
        // Counted as maximumFrameInterval (0.25 s) of a 0.65 s time constant: a partial step.
        XCTAssertGreaterThan(out.x, 0)
        XCTAssertLessThan(out.x, 1)
    }

    func testParametersAreSanitized() {
        var s = AdaptiveCursorSmoother(restSmoothing: .nan, speedResponse: -3)
        XCTAssertEqual(s.effectiveRestSmoothing, 0)
        XCTAssertEqual(s.effectiveSpeedResponse, 0)
        s.restSmoothing = 5
        s.speedResponse = .infinity
        XCTAssertEqual(s.effectiveRestSmoothing, CursorSmoother.smoothingRange.upperBound)
        XCTAssertEqual(s.effectiveSpeedResponse, 0)
        s.speedResponse = 100
        XCTAssertEqual(s.effectiveSpeedResponse, AdaptiveCursorSmoother.speedResponseRange.upperBound)

        var settings = AirTrackSettings()
        settings.cursorSpeedResponse = 50
        XCTAssertEqual(settings.sanitized.cursorSpeedResponse, AdaptiveCursorSmoother.speedResponseRange.upperBound)
        settings.cursorSpeedResponse = .nan
        XCTAssertEqual(settings.sanitized.cursorSpeedResponse, AirTrackSettings.default.cursorSpeedResponse)
        settings.cursorSpeedResponse = -1
        XCTAssertEqual(settings.sanitized.cursorSpeedResponse, 0)
    }

    func testRestTimeConstantMatchesThePhase2Meaning() {
        let s = AdaptiveCursorSmoother(restSmoothing: 0.35, speedResponse: 2)
        // exp(-dt / tau) at 30 fps must equal the per-frame EMA weight.
        XCTAssertEqual(exp(-dt / s.restTimeConstant), 0.35, accuracy: 1e-12)
        XCTAssertEqual(AdaptiveCursorSmoother(restSmoothing: 0, speedResponse: 2).restTimeConstant, 0)
        XCTAssertEqual(s.timeConstant(atSpeed: 0.5), s.restTimeConstant / 2, accuracy: 1e-12)
    }
}
