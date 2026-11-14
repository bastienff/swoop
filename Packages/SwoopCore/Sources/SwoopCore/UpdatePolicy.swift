import Foundation

/// A release version like `1.2.0` (or a tag like `v1.2.0`). Compared numerically, part by part;
/// missing parts count as 0 (`1.2` == `1.2.0`). Pre-release suffixes (`1.3.0-beta`) are not versions
/// Swoop offers, so they don't parse.
public struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ string: String) {
        var s = string.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.count <= 4, parts.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
        self.parts = parts.map { $0! }
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0
            let y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    public static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }

    public func hash(into hasher: inout Hasher) {
        var p = parts
        while p.last == 0 { p.removeLast() }
        hasher.combine(p)
    }
}

/// When the opt-in automatic update check runs, and what its answer means.
public enum UpdatePolicy {
    /// Automatic checks: at most one request per this interval.
    public static let interval: TimeInterval = 24 * 3600

    public static func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        // A clock set backwards would otherwise block checks until it catches up.
        return now.timeIntervalSince(lastCheck) >= interval || lastCheck > now
    }

    /// The latest release is an update for `current` only if both parse and it is strictly newer.
    public static func isUpdate(latest: String, current: String) -> Bool {
        guard let l = AppVersion(latest), let c = AppVersion(current) else { return false }
        return l > c
    }
}
