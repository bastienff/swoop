import Foundation

/// Decides when to run a coalesced refresh for a key (an app) from a stream of change events:
/// wait until events go quiet, but never longer than `maxWait` after the first pending event, and never
/// sooner than `minInterval` after the previous refresh. A constantly changing source (a terminal spinner
/// in a window title, bursts or one change a second) refreshes at a bounded rate instead of never — or on
/// every event.
public struct RefreshScheduler<Key: Hashable>: Sendable where Key: Sendable {
    public struct Policy: Sendable, Equatable {
        /// Fire once no new event arrived for this long.
        public var quiet: TimeInterval
        /// …but no later than this after the first event of the batch.
        public var maxWait: TimeInterval
        /// …and no sooner than this after the previous refresh of the key.
        public var minInterval: TimeInterval
        public init(quiet: TimeInterval, maxWait: TimeInterval, minInterval: TimeInterval = 0) {
            self.quiet = quiet; self.maxWait = maxWait; self.minInterval = minInterval
        }
    }

    private var pending: [Key: (first: Date, maxWait: TimeInterval, minInterval: TimeInterval)] = [:]
    private var lastFired: [Key: Date] = [:]

    public init() {}

    /// Records an event and returns the delay until the refresh should run (replacing any earlier schedule).
    /// Mixed events in one batch use the most urgent `maxWait` and `minInterval`.
    public mutating func event(_ key: Key, policy: Policy, now: Date = Date()) -> TimeInterval {
        var batch = pending[key] ?? (now, policy.maxWait, policy.minInterval)
        batch.maxWait = min(batch.maxWait, policy.maxWait)
        batch.minInterval = min(batch.minInterval, policy.minInterval)
        pending[key] = batch
        var fireAt = min(now.addingTimeInterval(policy.quiet), batch.first.addingTimeInterval(batch.maxWait))
        if let last = lastFired[key] { fireAt = max(fireAt, last.addingTimeInterval(batch.minInterval)) }
        return max(0, fireAt.timeIntervalSince(now))
    }

    /// The refresh ran: the next event starts a new batch.
    public mutating func fired(_ key: Key, now: Date = Date()) {
        pending[key] = nil
        lastFired[key] = now
    }

    /// Drops all state for a key (e.g. the app quit).
    public mutating func cancel(_ key: Key) { pending[key] = nil; lastFired[key] = nil }
}
