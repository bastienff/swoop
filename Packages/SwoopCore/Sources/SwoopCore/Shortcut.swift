import Foundation

/// A global keyboard shortcut: a virtual key code plus modifiers. Platform-neutral (no Carbon types).
public struct Shortcut: Codable, Sendable, Hashable {
    public struct Modifiers: OptionSet, Codable, Sendable, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    public var keyCode: UInt16
    public var modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers) { self.keyCode = keyCode; self.modifiers = modifiers }

    public static let tabKeyCode: UInt16 = 0x30
    /// ⌥Tab — PRD default.
    public static let `default` = Shortcut(keyCode: tabKeyCode, modifiers: [.option])

    public var isBareTab: Bool { keyCode == Self.tabKeyCode && modifiers.isEmpty }

    /// True when the shortcut has no modifier (would swallow a plain key system-wide).
    public var isUnmodified: Bool { modifiers.isEmpty }

    public var displayString: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    /// Known system/global shortcuts that commonly conflict. Not exhaustive.
    public static let knownSystemShortcuts: [Shortcut: String] = [
        Shortcut(keyCode: tabKeyCode, modifiers: [.command]): "macOS application switcher",
        Shortcut(keyCode: tabKeyCode, modifiers: [.command, .shift]): "macOS application switcher",
        Shortcut(keyCode: 0x31, modifiers: [.command]): "Spotlight",
        Shortcut(keyCode: 0x31, modifiers: [.control]): "Input source switching",
        Shortcut(keyCode: 0x32, modifiers: [.command]): "Cycle windows of the active app",
        Shortcut(keyCode: 0x31, modifiers: [.command, .option]): "Finder search window",
        Shortcut(keyCode: 0x0C, modifiers: [.command]): "Quit application",
        Shortcut(keyCode: 0x0D, modifiers: [.command]): "Close window",
        Shortcut(keyCode: 0x04, modifiers: [.command]): "Hide application",
        Shortcut(keyCode: 0x2E, modifiers: [.command]): "Minimize window",
    ]

    public var knownConflict: String? {
        if isBareTab { return "Tab is used by every app for focus and indentation" }
        return Self.knownSystemShortcuts[self]
    }

    public static func keyName(_ code: UInt16) -> String {
        let names: [UInt16: String] = [
            0x30: "Tab", 0x31: "Space", 0x24: "↩", 0x35: "⎋", 0x33: "⌫", 0x75: "⌦",
            0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑", 0x32: "`", 0x1B: "-", 0x18: "=",
            0x21: "[", 0x1E: "]", 0x29: ";", 0x27: "'", 0x2B: ",", 0x2F: ".", 0x2C: "/", 0x2A: "\\",
            0x00: "A", 0x0B: "B", 0x08: "C", 0x02: "D", 0x0E: "E", 0x03: "F", 0x05: "G", 0x04: "H",
            0x22: "I", 0x26: "J", 0x28: "K", 0x25: "L", 0x2E: "M", 0x2D: "N", 0x1F: "O", 0x23: "P",
            0x0C: "Q", 0x0F: "R", 0x01: "S", 0x11: "T", 0x20: "U", 0x09: "V", 0x0D: "W", 0x07: "X",
            0x10: "Y", 0x06: "Z", 0x1D: "0", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x17: "5",
            0x16: "6", 0x1A: "7", 0x1C: "8", 0x19: "9",
            0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6", 0x62: "F7",
            0x64: "F8", 0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
        ]
        return names[code] ?? "Key\(code)"
    }
}
