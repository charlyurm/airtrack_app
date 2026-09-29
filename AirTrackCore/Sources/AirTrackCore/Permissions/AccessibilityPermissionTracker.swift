import Foundation

/// Why the Accessibility permission is being re-checked.
public enum AccessibilityRefreshReason: String, Equatable, Sendable {
    /// App start: the permission may already exist.
    case launch
    /// The app became active again, typically after the user toggled it in System Settings.
    case appActivated
    /// The user pressed a button (turn on Cursor Control, request, check again).
    case userAction
    /// Low-rate background check while cursor control is on (detects revocation).
    case periodic

    /// Everything except the periodic check runs immediately.
    public var isThrottled: Bool { self == .periodic }
}

/// What the "grant permission" button should do.
public enum AccessibilityRequestAction: Equatable, Sendable {
    /// Already granted: nothing to ask.
    case none
    /// First time this session: let macOS show its prompt (adds AirTrack to the list).
    case showSystemPrompt
    /// The prompt was already shown: open System Settings instead (never prompt in a loop).
    case openSystemSettings
}

/// Accessibility permission state and its transitions, without any system API (PHASE 2.1
/// hotfix). The macOS layer supplies the real answer (`isTrusted`); this type decides WHEN to
/// ask, remembers the last answer and never repeats the system prompt.
///
/// - Never trusts a cached value for a user-visible transition: launch, app activation and
///   user actions always query the system.
/// - The periodic check is throttled to `periodicInterval`, so it can run on every metrics
///   tick without querying TCC more than once per second.
public struct AccessibilityPermissionTracker: Equatable, Sendable {
    public static let periodicInterval: TimeInterval = 1

    public private(set) var isGranted: Bool
    /// Whether the system prompt was already shown this session.
    public private(set) var hasShownPrompt = false
    public private(set) var lastCheck: TimeInterval?
    public private(set) var lastReason: AccessibilityRefreshReason = .launch

    /// - Parameter isTrusted: current system answer at launch.
    public init(isTrusted: Bool, at now: TimeInterval) {
        isGranted = isTrusted
        lastCheck = now
    }

    public func shouldCheck(for reason: AccessibilityRefreshReason, at now: TimeInterval) -> Bool {
        guard reason.isThrottled, let lastCheck, now.isFinite, lastCheck.isFinite, now >= lastCheck else { return true }
        return now - lastCheck >= Self.periodicInterval
    }

    /// Re-checks the permission when appropriate. `isTrusted` is only called if a check runs.
    /// - Returns: true when the permission changed (granted ↔ missing).
    @discardableResult
    public mutating func refresh(reason: AccessibilityRefreshReason, at now: TimeInterval, isTrusted: () -> Bool) -> Bool {
        guard shouldCheck(for: reason, at: now) else { return false }
        lastCheck = now
        lastReason = reason
        let granted = isTrusted()
        guard granted != isGranted else { return false }
        isGranted = granted
        return true
    }

    /// Decides what the request button does and records that the prompt was shown.
    public mutating func requestAction() -> AccessibilityRequestAction {
        if isGranted { return .none }
        if hasShownPrompt { return .openSystemSettings }
        hasShownPrompt = true
        return .showSystemPrompt
    }
}
