import Foundation

/// Platform-neutral description of a global shortcut. The macOS layer
/// registers it (Carbon RegisterEventHotKey or equivalent).
public struct KeyboardShortcut: Equatable, Hashable, Sendable, Codable {
    public struct Modifiers: OptionSet, Hashable, Sendable, Codable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    /// macOS virtual key code (kVK_*).
    public var keyCode: UInt16
    /// Human-readable key label, e.g. "A".
    public var key: String
    public var modifiers: Modifiers

    public init(keyCode: UInt16, key: String, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.key = key
        self.modifiers = modifiers
    }

    /// ⌃⌥⌘A. Replaces ⌘⇧A, which Finder uses for "Go to Applications".
    /// Absence of conflicts on the user's Mac is REQUIRES MACOS.
    public static let defaultEmergencyToggle = KeyboardShortcut(keyCode: 0x00, key: "A", modifiers: [.control, .option, .command])

    public var displayString: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + key
    }
}
