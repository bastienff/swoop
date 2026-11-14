import Foundation

/// When the open switcher loses focus, decides whether another app took it (take it back) or the user
/// meant to leave (respect it). Apps that launch, answer a script, or bring up their own window can still
/// take focus on macOS 14+, which used to close the switcher mid-typing.
public enum FocusStealPolicy {
    public enum Decision: Equatable, Sendable {
        /// Another app grabbed focus without the user's doing: re-activate and keep the switcher open.
        case reclaim
        /// The user (or the system) moved focus on purpose: behave as before.
        case respect
    }

    /// Reclaims per opening, so two apps never fight over focus.
    public static let maxReclaims = 2
    /// A click outside the panel this recent counts as the reason focus moved.
    public static let clickWindow: TimeInterval = 0.5
    /// A modifier pressed this recently means a keyboard shortcut moved focus, even if it's released now:
    /// ⌘Tab switches apps when ⌘ is *released*.
    public static let modifierWindow: TimeInterval = 1.0

    /// System UI that must always be allowed to take focus: authentication prompts, lock screen,
    /// Spotlight, Notification Center, Control Center, screenshots, Mission Control/Dock, Gatekeeper dialogs.
    public static let systemBundleIDs: Set<String> = [
        "com.apple.SecurityAgent", "com.apple.loginwindow", "com.apple.LocalAuthentication.UIAgent",
        "com.apple.Spotlight", "com.apple.notificationcenterui", "com.apple.controlcenter",
        "com.apple.screencaptureui", "com.apple.dock", "com.apple.systemuiserver",
        "com.apple.UserNotificationCenter", "com.apple.CoreServicesUIAgent", "com.apple.WindowManager",
    ]

    /// - Parameters:
    ///   - newFrontmostBundleID: the app that's frontmost now: nil if there's none (unknown), "" if it has
    ///     no bundle identifier.
    ///   - isOwnApp: focus went to another Swoop window (Settings, onboarding).
    ///   - heldModifiers: modifiers physically held now. Any held modifier means a keyboard shortcut the user
    ///     pressed (⌘Tab, ⌘Space, a launcher hotkey), except `ownHoldModifiers`.
    ///   - ownHoldModifiers: modifiers the user is holding *for Swoop* (switch-on-release), not a new shortcut.
    ///   - secondsSinceOutsideClick: time since the last click outside the panel, if any.
    ///   - secondsSinceModifier: time since a modifier other than the switcher's own was last held, if any.
    ///   - reclaimsSoFar: reclaims already done during this opening.
    public static func decide(newFrontmostBundleID: String?, isOwnApp: Bool, heldModifiers: Shortcut.Modifiers,
                              ownHoldModifiers: Shortcut.Modifiers = [], secondsSinceOutsideClick: TimeInterval?,
                              secondsSinceModifier: TimeInterval? = nil, reclaimsSoFar: Int) -> Decision {
        if isOwnApp { return .respect }
        guard let bundleID = newFrontmostBundleID, !systemBundleIDs.contains(bundleID) else { return .respect }
        if let click = secondsSinceOutsideClick, click < clickWindow { return .respect }
        if !heldModifiers.subtracting(.shift).subtracting(ownHoldModifiers).isEmpty { return .respect }
        if let modifier = secondsSinceModifier, modifier < modifierWindow { return .respect }
        if reclaimsSoFar >= maxReclaims { return .respect }
        return .reclaim
    }
}
