import XCTest
@testable import AirTrackCore

/// Hotfix 2.1: Accessibility permission transitions. The system answer (AXIsProcessTrusted /
/// CGPreflightPostEventAccess) is NOT simulated as if it were tested here: a closure stands in
/// for it, and these tests only cover when AirTrack asks and what it does with the answer.
final class AccessibilityPermissionTrackerTests: XCTestCase {
    /// Stand-in for the system: returns `value` and counts how often it was asked.
    private final class FakeSystem {
        var value: Bool
        var queries = 0
        init(_ value: Bool) { self.value = value }
        func ask() -> Bool {
            queries += 1
            return value
        }
    }

    private func state(_ granted: Bool, enabled: Bool = true, hand: Bool = true) -> CursorControlState {
        CursorControlState.resolve(enabled: enabled, paused: false, permissionGranted: granted, handAvailable: hand)
    }

    func testInitiallyGrantedNeverShowsWaitingForPermission() {
        let tracker = AccessibilityPermissionTracker(isTrusted: true, at: 0)
        XCTAssertTrue(tracker.isGranted)
        XCTAssertEqual(state(tracker.isGranted, hand: false), .waitingForHand)
        XCTAssertEqual(state(tracker.isGranted), .active)
    }

    func testInitiallyDeniedWaitsForPermission() {
        let tracker = AccessibilityPermissionTracker(isTrusted: false, at: 0)
        XCTAssertFalse(tracker.isGranted)
        XCTAssertEqual(state(tracker.isGranted), .waitingForPermission)
    }

    func testGrantDetectedWhenReturningToTheApp() {
        let system = FakeSystem(false)
        var tracker = AccessibilityPermissionTracker(isTrusted: system.ask(), at: 0)
        system.value = true // user switches AirTrack on in System Settings
        XCTAssertTrue(tracker.refresh(reason: .appActivated, at: 0.2, isTrusted: system.ask), "change reported")
        XCTAssertTrue(tracker.isGranted)
        XCTAssertEqual(state(tracker.isGranted, hand: false), .waitingForHand)
        XCTAssertEqual(state(tracker.isGranted), .active)
    }

    func testRevocationIsDetectedByThePeriodicCheck() {
        let system = FakeSystem(true)
        var tracker = AccessibilityPermissionTracker(isTrusted: system.ask(), at: 0)
        system.value = false
        XCTAssertTrue(tracker.refresh(reason: .periodic, at: 1.5, isTrusted: system.ask))
        XCTAssertFalse(tracker.isGranted)
        XCTAssertEqual(state(tracker.isGranted), .waitingForPermission)
    }

    func testActivationAndUserActionsAlwaysAskTheSystem() {
        let system = FakeSystem(false)
        var tracker = AccessibilityPermissionTracker(isTrusted: system.ask(), at: 10)
        // Immediately after launch, even within the periodic interval: not a cached value.
        tracker.refresh(reason: .appActivated, at: 10.01, isTrusted: system.ask)
        tracker.refresh(reason: .userAction, at: 10.02, isTrusted: system.ask)
        tracker.refresh(reason: .launch, at: 10.03, isTrusted: system.ask)
        XCTAssertEqual(system.queries, 4)
    }

    func testPeriodicCheckIsThrottledToOncePerSecond() {
        let system = FakeSystem(true)
        var tracker = AccessibilityPermissionTracker(isTrusted: system.ask(), at: 0)
        // Metrics arrive every 0.25 s for 3 s.
        for i in 1...12 { tracker.refresh(reason: .periodic, at: Double(i) * 0.25, isTrusted: system.ask) }
        XCTAssertEqual(system.queries, 1 + 3, "launch + one check per second")
    }

    func testNoStaleStateAfterRepeatedChanges() {
        let system = FakeSystem(false)
        var tracker = AccessibilityPermissionTracker(isTrusted: system.ask(), at: 0)
        let sequence = [true, true, false, true, false, false, true]
        for (i, value) in sequence.enumerated() {
            system.value = value
            tracker.refresh(reason: .appActivated, at: Double(i + 1), isTrusted: system.ask)
            XCTAssertEqual(tracker.isGranted, value, "step \(i)")
        }
    }

    func testUnchangedAnswerReportsNoChange() {
        var tracker = AccessibilityPermissionTracker(isTrusted: true, at: 0)
        XCTAssertFalse(tracker.refresh(reason: .appActivated, at: 1, isTrusted: { true }))
        XCTAssertEqual(tracker.lastReason, .appActivated)
    }

    func testSystemPromptIsShownAtMostOncePerSession() {
        var tracker = AccessibilityPermissionTracker(isTrusted: false, at: 0)
        XCTAssertEqual(tracker.requestAction(), .showSystemPrompt)
        for _ in 0..<20 {
            XCTAssertEqual(tracker.requestAction(), .openSystemSettings, "never prompt again")
        }
        XCTAssertTrue(tracker.hasShownPrompt)
    }

    func testNoRequestWhenAlreadyGranted() {
        var tracker = AccessibilityPermissionTracker(isTrusted: true, at: 0)
        XCTAssertEqual(tracker.requestAction(), .none)
        XCTAssertFalse(tracker.hasShownPrompt)
    }

    func testClockGoingBackwardsStillChecks() {
        let system = FakeSystem(true)
        var tracker = AccessibilityPermissionTracker(isTrusted: system.ask(), at: 100)
        tracker.refresh(reason: .periodic, at: 5, isTrusted: system.ask)
        XCTAssertEqual(system.queries, 2, "a clock reset must not block checks forever")
    }
}
