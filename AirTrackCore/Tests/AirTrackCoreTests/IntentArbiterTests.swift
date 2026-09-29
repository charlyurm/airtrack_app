import XCTest
@testable import AirTrackCore

/// PHASE 3A: one owner at a time, ambiguity → no commit, lifecycle transitions, and (scroll
/// fix) time-based maintenance: uncertainty holds, contradiction or timeout releases.
final class IntentArbiterTests: XCTestCase {
    private let dt = 1.0 / 30

    private func candidate(_ kind: GestureKind, ready: Bool = false, since: TimeInterval = 0) -> GestureCandidate {
        GestureCandidate(kind: kind, since: since, displacement: MotionVector(dx: 0, dy: ready ? 0.2 : 0.05),
                         axis: .vertical, evidence: ready ? 1 : 0.4, readyToCommit: ready, maintenance: nil)
    }

    private func owned(_ kind: GestureKind, _ evidence: MaintenanceEvidence) -> GestureCandidate {
        GestureCandidate(kind: kind, since: 0, displacement: .zero, axis: .none, evidence: 0, readyToCommit: false, maintenance: evidence)
    }

    /// Arbiter with `kind` committed at t = 0.
    private func committed(_ kind: GestureKind = .twoFingerScroll) -> IntentArbiter {
        var arbiter = IntentArbiter()
        arbiter.update(candidates: [candidate(kind, ready: true)], availability: .available, now: 0)
        return arbiter
    }

    func testCandidateThenCommitThenActive() {
        var arbiter = IntentArbiter()
        XCTAssertEqual(arbiter.update(candidates: [], availability: .available, now: 0).lifecycle, .idle)
        let c = arbiter.update(candidates: [candidate(.twoFingerScroll)], availability: .available, now: dt)
        XCTAssertEqual(c.lifecycle, .candidate)
        XCTAssertNil(c.owner)
        let confirmed = arbiter.update(candidates: [candidate(.twoFingerScroll, ready: true)], availability: .available, now: 2 * dt)
        XCTAssertEqual(confirmed.lifecycle, .confirmed)
        XCTAssertTrue(confirmed.committed)
        XCTAssertEqual(confirmed.owner, .twoFingerScroll)
        let active = arbiter.update(candidates: [owned(.twoFingerScroll, .supported)], availability: .available, now: 3 * dt)
        XCTAssertEqual(active.lifecycle, .active)
        XCTAssertTrue(active.held)
        XCTAssertFalse(active.committed, "commit happens once")
    }

    func testTwoReadyCandidatesAreAmbiguousAndCommitNothing() {
        var arbiter = IntentArbiter()
        let d = arbiter.update(candidates: [candidate(.twoFingerScroll, ready: true), candidate(.openHandScroll, ready: true)], availability: .available, now: 0)
        XCTAssertTrue(d.ambiguous)
        XCTAssertNil(d.owner)
        XCTAssertFalse(d.committed)
    }

    func testCandidateThatDisappearsIsCancelledThenIdle() {
        var arbiter = IntentArbiter()
        arbiter.update(candidates: [candidate(.openHandScroll)], availability: .available, now: 0)
        XCTAssertEqual(arbiter.update(candidates: [], availability: .available, now: dt).lifecycle, .cancelled)
        XCTAssertEqual(arbiter.update(candidates: [], availability: .available, now: 2 * dt).lifecycle, .idle)
    }

    // MARK: Maintenance (post-confirmation continuity)

    func testUncertaintyHoldsWithoutOutputWithinTheGrace() {
        var arbiter = committed()
        for i in 1...7 { // 0.233 s < 0.25 s
            let d = arbiter.update(candidates: [owned(.twoFingerScroll, .uncertain)], availability: .available, now: Double(i) * dt)
            XCTAssertEqual(d.owner, .twoFingerScroll, "frame \(i)")
            XCTAssertEqual(d.lifecycle, .suspended)
            XCTAssertFalse(d.held, "no output while uncertain")
        }
        let back = arbiter.update(candidates: [owned(.twoFingerScroll, .supported)], availability: .available, now: 8 * dt)
        XCTAssertEqual(back.lifecycle, .active)
        XCTAssertTrue(back.held)
    }

    func testProlongedUncertaintyReleasesAfterTheGraceWithoutInertia() {
        var arbiter = committed()
        var released: IntentArbiter.Decision?
        for i in 1...20 {
            let d = arbiter.update(candidates: [owned(.twoFingerScroll, .uncertain)], availability: .available, now: Double(i) * dt)
            if d.released != nil { released = d; XCTAssertEqual(i, 8, "0.267 s > 0.25 s"); break }
        }
        XCTAssertEqual(released?.released, .recognitionTimeout)
        XCTAssertEqual(released?.releasedFresh, false, "stale motion never starts inertia")
        XCTAssertNil(arbiter.owner)
    }

    func testSupportResetsTheGrace() {
        var arbiter = committed()
        // Alternating uncertain / supported for 2 s never releases.
        for i in 1...60 {
            let evidence: MaintenanceEvidence = i.isMultiple(of: 3) ? .supported : .uncertain
            XCTAssertNotNil(arbiter.update(candidates: [owned(.twoFingerScroll, evidence)], availability: .available, now: Double(i) * dt).owner)
        }
    }

    func testContradictionEndsImmediatelyAndFreshly() {
        var arbiter = committed()
        arbiter.update(candidates: [owned(.twoFingerScroll, .supported)], availability: .available, now: dt)
        let end = arbiter.update(candidates: [owned(.twoFingerScroll, .contradicted)], availability: .available, now: 2 * dt)
        XCTAssertEqual(end.released, .gestureEnded)
        XCTAssertTrue(end.releasedFresh)
        XCTAssertEqual(end.lifecycle, .releasing)
    }

    func testContradictionAfterALongHoldIsNotFresh() {
        var arbiter = committed()
        arbiter.update(candidates: [owned(.twoFingerScroll, .uncertain)], availability: .available, now: 0.2)
        let end = arbiter.update(candidates: [owned(.twoFingerScroll, .contradicted)], availability: .available, now: 0.22)
        XCTAssertEqual(end.released, .gestureEnded)
        XCTAssertFalse(end.releasedFresh)
    }

    func testTrackingGapHoldsAndRecovers() {
        var arbiter = committed()
        let gap = arbiter.update(candidates: [], availability: .gap, now: dt)
        XCTAssertEqual(gap.lifecycle, .suspended)
        XCTAssertEqual(gap.owner, .twoFingerScroll)
        XCTAssertFalse(gap.held)
        let back = arbiter.update(candidates: [owned(.twoFingerScroll, .supported)], availability: .available, now: 2 * dt)
        XCTAssertEqual(back.lifecycle, .active)
        XCTAssertTrue(back.held)
    }

    func testLimitedTrackingCanKeepButNeverStart() {
        var arbiter = committed()
        let kept = arbiter.update(candidates: [owned(.twoFingerScroll, .supported)], availability: .limited, now: dt)
        XCTAssertTrue(kept.held, "a partial view keeps a committed scroll")

        var fresh = IntentArbiter()
        let d = fresh.update(candidates: [candidate(.twoFingerScroll, ready: true)], availability: .limited, now: 0)
        XCTAssertNil(d.owner, "a partial view never starts one")
    }

    func testLostReleasesAtOnce() {
        var arbiter = committed()
        let lost = arbiter.update(candidates: [], availability: .lost, now: dt)
        XCTAssertEqual(lost.released, .trackingLost)
        XCTAssertFalse(lost.releasedFresh)
    }

    func testCandidatesNeedFreshFeatures() {
        var arbiter = IntentArbiter()
        arbiter.update(candidates: [candidate(.twoFingerScroll)], availability: .available, now: 0)
        let gap = arbiter.update(candidates: [candidate(.twoFingerScroll, ready: true)], availability: .gap, now: dt)
        XCTAssertNil(gap.owner, "never commits without fresh landmarks")
        XCTAssertEqual(gap.lifecycle, .cancelled)
    }

    func testCandidateStartTimeIsKeptWhileTheKindStaysTheSame() {
        var arbiter = IntentArbiter()
        arbiter.update(candidates: [candidate(.twoFingerScroll, since: 1)], availability: .available, now: 1)
        arbiter.update(candidates: [candidate(.twoFingerScroll, since: 1)], availability: .available, now: 1.1)
        XCTAssertEqual(arbiter.candidateStarts[.twoFingerScroll], 1)
        arbiter.update(candidates: [candidate(.openHandScroll, since: 2)], availability: .available, now: 2)
        XCTAssertEqual(arbiter.candidateStarts, [.openHandScroll: 2])
    }

    func testCancelAllEndsEverything() {
        var arbiter = committed()
        XCTAssertEqual(arbiter.cancelAll(), .twoFingerScroll)
        XCTAssertNil(arbiter.owner)
        XCTAssertEqual(arbiter.lifecycle, .idle)
    }
}
