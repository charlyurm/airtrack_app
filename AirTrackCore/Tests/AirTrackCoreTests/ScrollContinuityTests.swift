import XCTest
@testable import AirTrackCore

/// PHASE 3A scroll fix: reproduces the physical failures (scroll interrupted, cursor frozen,
/// TWO_FINGER lost, downward worse than upward, "goes crazy") and pins the fixed behavior:
/// precision before commit, temporal continuity after commit, safety on tracking loss.
final class ScrollContinuityTests: XCTestCase {
    private let dt = InteractionScenario.dt

    /// Continuous hand; each frame can override pose, omitted joints and tracking mode.
    private struct Session {
        var engine = InteractionEngine()
        var frame = 0
        var center = Point2D(x: 0.5, y: 0.3)

        mutating func step(
            _ fingers: FingerSet,
            _ thumb: TestPoses.Thumb = .folded,
            move: Point2D,
            omit: Set<HandJoint> = [],
            mode: PointerTrackingMode = .full,
            live: Bool = true
        ) -> InteractionFrame {
            let t = Double(frame) * InteractionScenario.dt
            frame += 1
            center = center + move
            let hand = TestPoses.hand(extended: fingers, thumb: thumb, at: t, center: center, omit: omit)
            return InteractionScenario.feed(&engine, mode.providesPointer ? hand : nil, mode: mode, at: t, live: live)
        }

        mutating func run(_ fingers: FingerSet, _ thumb: TestPoses.Thumb = .folded, move: Point2D, count: Int,
                          omit: Set<HandJoint> = [], mode: PointerTrackingMode = .full) -> [InteractionFrame] {
            (0..<count).map { _ in step(fingers, thumb, move: move, omit: omit, mode: mode) }
        }
    }

    private func deltas(_ frames: [InteractionFrame]) -> [Int] { InteractionScenario.scrolls(frames).map(\.delta) }
    private let down = Point2D(x: 0, y: 0.01)
    private let up = Point2D(x: 0, y: -0.01)
    /// Index and middle both unmeasurable: the finger evidence is genuinely uncertain.
    private let blurredFingers: Set<HandJoint> = [.indexDIP, .middleDIP]

    /// Commits a two-finger scroll moving down (frames 0…5).
    private func scrolling() -> Session {
        var s = Session()
        _ = s.run(TestPoses.twoFingers, move: down, count: 6)
        XCTAssertEqual(s.engine.arbiter.owner, .twoFingerScroll)
        return s
    }

    // TEST 1
    func testTwoFingerScrollStaysActiveWhileSpeedVaries() {
        var s = scrolling()
        var frames: [InteractionFrame] = []
        for speed in [0.004, 0.02, 0.006, 0.03, 0.01, 0.002, 0.025] {
            frames += s.run(TestPoses.twoFingers, move: Point2D(x: 0, y: speed), count: 3)
        }
        XCTAssertTrue(frames.allSatisfy { $0.intent == .twoFingerScroll && $0.cursorPolicy == .frozen })
        XCTAssertTrue(deltas(frames).allSatisfy { $0 > 0 })
    }

    // TEST 2
    func testOneUncertainFrameDoesNotEndTheScroll() {
        var s = scrolling()
        let blur = s.step(TestPoses.twoFingers, move: down, omit: blurredFingers)
        XCTAssertEqual(blur.intent, .twoFingerScroll)
        XCTAssertEqual(blur.lifecycle, .suspended)
        XCTAssertTrue(blur.actions.isEmpty, "no invented motion while uncertain")
        XCTAssertEqual(blur.cursorPolicy, .frozen)
        let back = s.run(TestPoses.twoFingers, move: down, count: 3)
        XCTAssertTrue(back.allSatisfy { $0.lifecycle == .active })
        XCTAssertFalse(deltas(back).isEmpty)
        XCTAssertTrue(InteractionScenario.scrolls(back).allSatisfy { $0.phase == .changed }, "same scroll, no new began")
    }

    func testOneUnknownFingerKeepsTheScrollSupported() {
        var s = scrolling()
        // Only the middle finger is unmeasurable (index still clearly extended).
        let frames = s.run(TestPoses.twoFingers, move: down, count: 4, omit: [.middleDIP])
        XCTAssertTrue(frames.allSatisfy { $0.maintenance == .supported && $0.lifecycle == .active })
        XCTAssertEqual(deltas(frames).count, 4)
    }

    // TEST 3
    func testProlongedUncertaintyHoldsBrieflyThenReleases() {
        var s = scrolling()
        var frames: [InteractionFrame] = []
        for _ in 0..<12 { frames.append(s.step(TestPoses.twoFingers, move: down, omit: blurredFingers)) }
        // Last supported at frame 5; 0.25 s grace → frames 6…12 hold (≤ 0.233 s), release at +0.267 s.
        let releaseIndex = frames.firstIndex { $0.released != nil }
        XCTAssertEqual(releaseIndex, 7)
        XCTAssertEqual(frames[releaseIndex ?? 0].released, .recognitionTimeout)
        XCTAssertTrue(frames[..<(releaseIndex ?? 0)].allSatisfy { $0.lifecycle == .suspended && $0.actions.isEmpty })
        let closing = InteractionScenario.scrolls(Array(frames[(releaseIndex ?? 0)...]))
        XCTAssertEqual(closing, [ScrollAction(delta: 0, phase: .ended)], "ended, and no inertia from stale motion")
        XCTAssertEqual(frames.last?.cursorPolicy, .follow, "the cursor is released")
    }

    // TEST 4 & 5
    func testOpenHandUpAndDownAreSymmetric() {
        var upward = Session()
        upward.center = Point2D(x: 0.5, y: 0.6)
        let upFrames = upward.run(TestPoses.fourFingers, .extended, move: up, count: 20)
        var downward = Session()
        downward.center = Point2D(x: 0.5, y: 0.3)
        let downFrames = downward.run(TestPoses.fourFingers, .extended, move: down, count: 20)

        XCTAssertEqual(upFrames.firstIndex { $0.intent != nil }, downFrames.firstIndex { $0.intent != nil })
        let upDeltas = deltas(upFrames)
        let downDeltas = deltas(downFrames)
        XCTAssertTrue(upDeltas.allSatisfy { $0 < 0 })
        XCTAssertTrue(downDeltas.allSatisfy { $0 > 0 })
        XCTAssertEqual(upDeltas.count, downDeltas.count)
        // Same magnitude, opposite sign (±1 point of carried fraction at most).
        XCTAssertTrue(zip(upDeltas, downDeltas).allSatisfy { abs(abs($0) - $1) <= 1 }, "\(upDeltas) vs \(downDeltas)")
        XCTAssertTrue(upFrames.suffix(15).allSatisfy { $0.lifecycle == .active })
        XCTAssertTrue(downFrames.suffix(15).allSatisfy { $0.lifecycle == .active })
    }

    /// Moving down, the lowest joints (wrist, little-finger knuckle) drop in and out near the
    /// bottom of the image. That must never look like movement (it used to shift the palm
    /// center → wrong-direction spikes, "goes crazy") and must not end the scroll.
    func testLowerJointsDroppingOutNeitherJumpsNorStopsTheScroll() {
        var s = scrolling()
        var frames: [InteractionFrame] = []
        for i in 0..<16 {
            let dropped: Set<HandJoint> = i.isMultiple(of: 2) ? [.wrist, .pinkyMCP] : []
            frames.append(s.step(TestPoses.twoFingers, move: down, omit: dropped, mode: dropped.isEmpty ? .full : .partial))
        }
        let d = deltas(frames)
        XCTAssertEqual(d.count, 16, "every frame scrolls")
        let reference = d[0]
        XCTAssertTrue(d.allSatisfy { abs($0 - reference) <= 2 }, "no spikes: \(d)")
        XCTAssertTrue(frames.allSatisfy { $0.intent == .twoFingerScroll })
    }

    func testImplausibleOneFrameJumpIsIgnored() {
        var s = scrolling()
        let normal = deltas(s.run(TestPoses.twoFingers, move: down, count: 3))
        let glitch = s.step(TestPoses.twoFingers, move: Point2D(x: 0, y: 0.25))      // detection glitch
        let back = s.step(TestPoses.twoFingers, move: Point2D(x: 0, y: -0.24))       // and back
        XCTAssertTrue(glitch.actions.isEmpty && back.actions.isEmpty, "a 60+ scales/s jump is not a hand")
        XCTAssertEqual(back.intent, .twoFingerScroll)
        let after = deltas(s.run(TestPoses.twoFingers, move: down, count: 3))
        XCTAssertTrue(after.allSatisfy { $0 <= (normal.max() ?? 0) + 2 })
    }

    // TEST 6
    func testFastVerticalMovementStaysActive() {
        var s = Session()
        let frames = s.run(TestPoses.twoFingers, move: Point2D(x: 0, y: 0.03), count: 14)
        let committed = frames.firstIndex { $0.intent != nil } ?? 99
        XCTAssertLessThanOrEqual(committed, 3)
        XCTAssertTrue(frames[committed...].allSatisfy { $0.intent == .twoFingerScroll })
        XCTAssertEqual(deltas(frames).count, frames.count - committed, "every frame scrolls")
    }

    // TEST 7
    func testDiagonalStillNeverCommits() {
        var s = Session()
        s.center = Point2D(x: 0.3, y: 0.3)
        let frames = s.run(TestPoses.twoFingers, move: Point2D(x: 0.01, y: 0.01), count: 14)
        XCTAssertTrue(frames.allSatisfy { $0.intent == nil && $0.actions.isEmpty })
    }

    func testUncertainPoseStillNeverStartsAScroll() {
        var s = Session()
        let frames = s.run(TestPoses.twoFingers, move: down, count: 15, omit: blurredFingers)
        XCTAssertTrue(frames.allSatisfy { $0.intent == nil && $0.candidate == nil })
    }

    // TEST 8
    func testRealTerminationEndsPromptly() {
        var s = scrolling()
        let frames = s.run(TestPoses.pointing, move: down, count: 4)
        XCTAssertEqual(frames.firstIndex { $0.released == .gestureEnded }, 1, "stable pointing = clear end (2 frames)")
        XCTAssertEqual(frames.last?.cursorPolicy, .follow)
        XCTAssertEqual(InteractionScenario.scrolls(frames).first, ScrollAction(delta: 0, phase: .ended))
    }

    // TEST 9
    func testTrackingLostNeverScrollsIndefinitely() {
        var s = scrolling()
        _ = s.step(TestPoses.twoFingers, move: down, mode: .holding)
        let lost = s.run(TestPoses.twoFingers, move: down, count: 60, mode: .lost)
        XCTAssertEqual(InteractionScenario.scrolls(lost), [ScrollAction(delta: 0, phase: .ended)])
        XCTAssertTrue(lost.allSatisfy { $0.intent == nil && $0.cursorPolicy == .follow })
    }

    func testHoldLongerThanTheGraceWithoutLostStillReleases() {
        // Defensive: even if HOLD were reported for long, the grace bounds the frozen cursor.
        var s = scrolling()
        let hold = s.run(TestPoses.twoFingers, move: down, count: 12, mode: .holding)
        XCTAssertEqual(hold.first { $0.released != nil }?.released, .recognitionTimeout)
        XCTAssertEqual(hold.last?.cursorPolicy, .follow)
    }

    // TEST 10 (Phase 2.1 protection at the interaction boundary)
    func testWithoutAGestureTheCursorIsNeverFrozen() {
        var s = Session()
        let frames = s.run(TestPoses.pointing, move: Point2D(x: 0.004, y: 0.01), count: 30)
            + s.run(TestPoses.pointing, move: down, count: 5, omit: [.wrist], mode: .partial)
        XCTAssertTrue(frames.allSatisfy { $0.cursorPolicy == .follow && $0.actions.isEmpty })
    }
}
