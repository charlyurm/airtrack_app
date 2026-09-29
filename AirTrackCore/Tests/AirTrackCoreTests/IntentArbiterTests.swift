import XCTest
@testable import AirTrackCore

/// PHASE 3A-1: one owner at a time, ambiguity → no commit, lifecycle transitions.
final class IntentArbiterTests: XCTestCase {
    private func candidate(_ kind: GestureKind, ready: Bool = false, continues: Bool = false, since: TimeInterval = 0) -> GestureCandidate {
        GestureCandidate(kind: kind, since: since, displacement: MotionVector(dx: 0, dy: ready ? 0.2 : 0.05),
                         axis: .vertical, evidence: ready ? 1 : 0.4, readyToCommit: ready, continuesActive: continues)
    }

    func testCandidateThenCommitThenActive() {
        var arbiter = IntentArbiter()
        XCTAssertEqual(arbiter.update(candidates: [], availability: .available).lifecycle, .idle)
        let c = arbiter.update(candidates: [candidate(.twoFingerScroll)], availability: .available)
        XCTAssertEqual(c.lifecycle, .candidate)
        XCTAssertNil(c.owner)
        let confirmed = arbiter.update(candidates: [candidate(.twoFingerScroll, ready: true)], availability: .available)
        XCTAssertEqual(confirmed.lifecycle, .confirmed)
        XCTAssertTrue(confirmed.committed)
        XCTAssertEqual(confirmed.owner, .twoFingerScroll)
        let active = arbiter.update(candidates: [candidate(.twoFingerScroll, continues: true)], availability: .available)
        XCTAssertEqual(active.lifecycle, .active)
        XCTAssertTrue(active.held)
        XCTAssertFalse(active.committed, "commit happens once")
    }

    func testTwoReadyCandidatesAreAmbiguousAndCommitNothing() {
        var arbiter = IntentArbiter()
        let d = arbiter.update(candidates: [candidate(.twoFingerScroll, ready: true), candidate(.openHandScroll, ready: true)], availability: .available)
        XCTAssertTrue(d.ambiguous)
        XCTAssertNil(d.owner)
        XCTAssertFalse(d.committed)
    }

    func testCandidateThatDisappearsIsCancelledThenIdle() {
        var arbiter = IntentArbiter()
        arbiter.update(candidates: [candidate(.openHandScroll)], availability: .available)
        XCTAssertEqual(arbiter.update(candidates: [], availability: .available).lifecycle, .cancelled)
        XCTAssertEqual(arbiter.update(candidates: [], availability: .available).lifecycle, .idle)
    }

    func testOwnerSurvivesOneMissingFrameAndReleasesAfterTwo() {
        var arbiter = IntentArbiter()
        arbiter.update(candidates: [candidate(.twoFingerScroll, ready: true)], availability: .available)
        let first = arbiter.update(candidates: [], availability: .available)
        XCTAssertEqual(first.owner, .twoFingerScroll)
        XCTAssertFalse(first.held, "no output while the pose is missing")
        let second = arbiter.update(candidates: [], availability: .available)
        XCTAssertNil(second.owner)
        XCTAssertEqual(second.released, .gestureEnded)
        XCTAssertEqual(second.lifecycle, .releasing)
    }

    func testTrackingGapSuspendsAndRecoveryResumes() {
        var arbiter = IntentArbiter()
        arbiter.update(candidates: [candidate(.twoFingerScroll, ready: true)], availability: .available)
        let gap = arbiter.update(candidates: [], availability: .gap)
        XCTAssertEqual(gap.lifecycle, .suspended)
        XCTAssertEqual(gap.owner, .twoFingerScroll)
        XCTAssertFalse(gap.held)
        let back = arbiter.update(candidates: [candidate(.twoFingerScroll, continues: true)], availability: .available)
        XCTAssertEqual(back.lifecycle, .active)
        XCTAssertTrue(back.held)
    }

    func testLostAndDegradedTrackingRelease() {
        var lost = IntentArbiter()
        lost.update(candidates: [candidate(.twoFingerScroll, ready: true)], availability: .available)
        lost.update(candidates: [], availability: .gap)
        XCTAssertEqual(lost.update(candidates: [], availability: .lost).released, .trackingLost)

        var degraded = IntentArbiter()
        degraded.update(candidates: [candidate(.openHandScroll, ready: true)], availability: .available)
        XCTAssertEqual(degraded.update(candidates: [], availability: .degraded).released, .trackingDegraded)
    }

    func testCandidatesNeedFreshFeatures() {
        var arbiter = IntentArbiter()
        arbiter.update(candidates: [candidate(.twoFingerScroll)], availability: .available)
        let gap = arbiter.update(candidates: [candidate(.twoFingerScroll, ready: true)], availability: .gap)
        XCTAssertNil(gap.owner, "never commits without fresh landmarks")
        XCTAssertEqual(gap.lifecycle, .cancelled)
    }

    func testCandidateStartTimeIsKeptWhileTheKindStaysTheSame() {
        var arbiter = IntentArbiter()
        arbiter.update(candidates: [candidate(.twoFingerScroll, since: 1)], availability: .available)
        arbiter.update(candidates: [candidate(.twoFingerScroll, since: 1)], availability: .available)
        XCTAssertEqual(arbiter.candidateStarts[.twoFingerScroll], 1)
        arbiter.update(candidates: [candidate(.openHandScroll, since: 2)], availability: .available)
        XCTAssertEqual(arbiter.candidateStarts, [.openHandScroll: 2])
    }

    func testCancelAllEndsEverything() {
        var arbiter = IntentArbiter()
        arbiter.update(candidates: [candidate(.twoFingerScroll, ready: true)], availability: .available)
        XCTAssertEqual(arbiter.cancelAll(), .twoFingerScroll)
        XCTAssertNil(arbiter.owner)
        XCTAssertEqual(arbiter.lifecycle, .idle)
    }
}
