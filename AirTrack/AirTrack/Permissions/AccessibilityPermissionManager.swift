import AppKit
import ApplicationServices
import CoreGraphics
import Security

/// Permission to post input events (moving the cursor). macOS lists it under
/// System Settings → Privacy & Security → Accessibility.
///
/// TCC has two services behind that one list, and the grant is checked on the RUNNING process:
/// - Accessibility (`AXIsProcessTrusted`): what the "+" button and the prompt of
///   `AXIsProcessTrustedWithOptions` grant. An Accessibility-trusted process can post events.
/// - PostEvent (`CGPreflightPostEventAccess`): what `CGRequestPostEventAccess` asks for.
/// Phase 2 only checked PostEvent, so an Accessibility grant (e.g. added manually with "+",
/// or after `tccutil reset Accessibility`) could show as allowed in System Settings while
/// AirTrack reported it missing. Either grant is enough to move the cursor.
///
/// Both answers are for the code signature that is running. With ad-hoc signing ("Sign to
/// Run Locally") that signature changes on every build, so an entry made for an older build
/// stays switched on in System Settings but no longer applies (see PERMISSIONS.md).
enum AccessibilityPermissionManager {
    /// Accessibility service. Queried live on every call.
    static var isProcessTrusted: Bool { AXIsProcessTrusted() }

    /// PostEvent service.
    static var canPostEvents: Bool { CGPreflightPostEventAccess() }

    /// Cheap check, no UI: may AirTrack post mouse events right now?
    static var isGranted: Bool { isProcessTrusted || canPostEvents }

    /// Shows the system Accessibility prompt, which also adds this exact build to the list.
    /// The app cannot grant itself the permission; the user must switch it on. Call only from
    /// an explicit user action, at most once per session (AccessibilityPermissionTracker).
    static func request() {
        // String key instead of the kAXTrustedCheckOptionPrompt global, which is a mutable
        // global under Swift 6 strict concurrency. Same value.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        Log.permissions.info("Accessibility prompt requested; trusted now: \(trusted, privacy: .public)")
    }

    @MainActor
    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// What macOS sees when it evaluates the permission for THIS process (debug panel and logs).
struct AccessibilityDiagnostics: Equatable, Sendable {
    enum Signature: Equatable, Sendable {
        case adHoc
        case team(String)
        case other
        case unknown
    }

    var processTrusted: Bool
    var canPostEvents: Bool
    var bundleIdentifier: String
    /// Executable of the running process, with the home folder shortened to "~".
    var executablePath: String
    var signature: Signature

    static func current() -> AccessibilityDiagnostics {
        AccessibilityDiagnostics(
            processTrusted: AccessibilityPermissionManager.isProcessTrusted,
            canPostEvents: AccessibilityPermissionManager.canPostEvents,
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "—",
            executablePath: shortened(Bundle.main.executablePath ?? "—"),
            signature: signatureOfSelf()
        )
    }

    var signatureLabel: String {
        switch signature {
        case .adHoc: "ad-hoc (Sign to Run Locally)"
        case let .team(team): "Team \(team)"
        case .other: "sin equipo"
        case .unknown: "desconocida"
        }
    }

    private static func shortened(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + String(path.dropFirst(home.count)) : path
    }

    private static func signatureOfSelf() -> Signature {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return .unknown }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return .unknown }
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: UInt32(kSecCSSigningInformation))
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
              let info = information as? [String: Any] else { return .unknown }
        if let team = info[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty {
            return .team(team)
        }
        let signatureFlags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        return signatureFlags & SecCodeSignatureFlags.adhoc.rawValue != 0 ? .adHoc : .other
    }
}
