import Foundation

/// What happened this session, for the diagnostics report: did the shortcut fire, did the switcher open,
/// how did switches end. Counters and app names only, never window titles. Lives in memory, like the log.
@MainActor
final class SessionStats {
    static let shared = SessionStats()

    struct Activation {
        let at: Date
        let app: String
        let route: String
        let outcome: String
        let milliseconds: Int
    }

    private(set) var shortcutPresses = 0
    private(set) var panelOpens = 0
    /// Shortcut or menu pressed while Accessibility wasn't granted (onboarding shown instead).
    private(set) var blockedOpens = 0
    private(set) var outcomes: [String: Int] = [:]
    /// Apps that took focus from the open switcher, and how often (bundle id or name).
    private(set) var focusTakers: [String: Int] = [:]
    private(set) var recent: [Activation] = []
    static let recentLimit = 25

    func shortcutPressed() { shortcutPresses += 1 }
    func panelOpened() { panelOpens += 1 }
    func openBlocked() { blockedOpens += 1 }
    func focusTaken(by app: String) { focusTakers[app, default: 0] += 1 }

    func activation(app: String, route: String, outcome: String, since start: Date) {
        outcomes[outcome, default: 0] += 1
        recent.append(Activation(at: start, app: app, route: route, outcome: outcome,
                                 milliseconds: Int(Date().timeIntervalSince(start) * 1000)))
        if recent.count > Self.recentLimit { recent.removeFirst(recent.count - Self.recentLimit) }
    }
}
