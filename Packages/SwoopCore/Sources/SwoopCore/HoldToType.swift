import Foundation

/// Hold-and-type: in switch-on-release mode the shortcut's modifier stays held while you type, so ⌥A
/// would type "å" (and ⌘ or ⌃ letters would be commands). The panel reads each key as its plain
/// character instead, then switches to the top match when the modifier is released.
public enum HoldToType {
    /// The text a key press adds to the query, given the event's `charactersIgnoringModifiers`; nil for
    /// keys that don't type (Return, Escape, Tab, Delete, arrows, function keys, other control characters).
    public static func text(_ charactersIgnoringModifiers: String?) -> String? {
        guard let s = charactersIgnoringModifiers, !s.isEmpty else { return nil }
        for u in s.unicodeScalars where u.value < 0x20 || u.value == 0x7F || (0xF700...0xF8FF).contains(u.value) {
            return nil
        }
        return s
    }
}
