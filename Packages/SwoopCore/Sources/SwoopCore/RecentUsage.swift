import Foundation

/// Pure MRU bookkeeping. Persisted by the app (JSON in Application Support).
public struct RecentUsage: Codable, Sendable, Equatable {
    public private(set) var lastUsed: [String: Date] = [:]
    public var capacity: Int

    public init(capacity: Int = 500) { self.capacity = capacity }

    /// Leading status glyphs (spinners like "◐ ", dirty markers "● ") are dropped so a window keeps
    /// its recency while an app animates its title.
    public static func key(bundleID: String, title: String) -> String {
        let trimmed = title.drop { !$0.isLetter && !$0.isNumber }
        return "\(bundleID)\u{1F}\(trimmed.isEmpty ? Substring(title) : trimmed)"
    }

    public mutating func record(_ key: String, at date: Date = Date()) {
        lastUsed[key] = date
        if lastUsed.count > capacity {
            let drop = lastUsed.sorted { $0.value < $1.value }.prefix(lastUsed.count - capacity)
            for (k, _) in drop { lastUsed.removeValue(forKey: k) }
        }
    }

    public func date(for key: String) -> Date? { lastUsed[key] }

    public mutating func reset() { lastUsed.removeAll() }
}
