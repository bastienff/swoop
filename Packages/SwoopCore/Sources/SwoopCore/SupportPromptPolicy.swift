import Foundation

/// Persistent state of the "buy me a coffee / star on GitHub" card.
public struct SupportPromptState: Codable, Equatable, Sendable {
    /// When Swoop first ran (first prompt is not before `firstSeen + interval`).
    public var firstSeen: Date
    /// Earliest date for the next prompt (set by "Maybe later"); nil → `firstSeen + interval`.
    public var nextDue: Date?
    /// Successful switches made with Swoop (shown on the card, and a minimum before asking).
    public var switches: Int
    /// Never ask again (the user supported, or chose "Don't ask again").
    public var optedOut: Bool
    public var timesShown: Int

    public init(firstSeen: Date, nextDue: Date? = nil, switches: Int = 0, optedOut: Bool = false, timesShown: Int = 0) {
        self.firstSeen = firstSeen; self.nextDue = nextDue; self.switches = switches
        self.optedOut = optedOut; self.timesShown = timesShown
    }
}

/// When to show the support card. First time: after 100 switches or 2 days of use, whichever comes
/// first (the time path still needs a little real use). Then every 2 days after "Maybe later". Never
/// again once the user helped or chose "Don't ask again".
public enum SupportPromptPolicy {
    public static let interval: TimeInterval = 2 * 24 * 3600
    /// Shows the first card right away at this many switches (first time only).
    public static let firstPromptSwitches = 100
    /// Minimum switches for the time-based path.
    public static let minimumSwitches = 10

    public static func dueDate(_ s: SupportPromptState) -> Date { s.nextDue ?? s.firstSeen.addingTimeInterval(interval) }

    public static func isDue(_ s: SupportPromptState, now: Date) -> Bool {
        guard !s.optedOut else { return false }
        if s.timesShown == 0 && s.switches >= firstPromptSwitches { return true }
        return s.switches >= minimumSwitches && now >= dueDate(s)
    }

    public enum Outcome: Sendable { case supported, later, never }

    /// State after the card was answered (or ignored, which counts as `.later`).
    public static func resolve(_ s: SupportPromptState, _ outcome: Outcome, now: Date) -> SupportPromptState {
        var s = s
        s.timesShown += 1
        switch outcome {
        case .supported, .never: s.optedOut = true
        case .later: s.nextDue = now.addingTimeInterval(interval)
        }
        return s
    }
}
