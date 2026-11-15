import Foundation

/// A user-chosen list of apps, stored by bundle ID (survives renames, moves and updates). The name is
/// kept only for display, so the list still reads well when the app isn't installed any more.
/// Used twice: apps hidden from the switcher, and apps in which the global shortcut is ignored.
public struct AppList: Codable, Equatable, Sendable {
    public struct App: Codable, Equatable, Hashable, Sendable, Identifiable {
        public var bundleID: String
        public var name: String
        public var id: String { bundleID.lowercased() }
        public init(bundleID: String, name: String) { self.bundleID = bundleID; self.name = name }
    }

    /// Sorted by name.
    public private(set) var apps: [App]

    public init(_ apps: [App] = []) {
        self.apps = []
        for app in apps { add(app) }
    }

    public var isEmpty: Bool { apps.isEmpty }

    /// Bundle IDs compare case-insensitively (macOS treats them that way).
    public func contains(_ bundleID: String?) -> Bool {
        guard let id = bundleID?.lowercased(), !id.isEmpty else { return false }
        return apps.contains { $0.id == id }
    }

    /// Adds an app once; a second add with the same bundle ID only refreshes its name.
    public mutating func add(_ app: App) {
        guard !app.bundleID.isEmpty else { return }
        apps.removeAll { $0.id == app.id }
        apps.append(app)
        apps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public mutating func remove(_ bundleID: String) {
        let id = bundleID.lowercased()
        apps.removeAll { $0.id == id }
    }

    /// Decoding goes through `init(_:)`, so stored lists are re-sorted and de-duplicated.
    public init(from decoder: Decoder) throws {
        self.init(try decoder.singleValueContainer().decode([App].self))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(apps)
    }
}

/// Whether the global shortcut should be released for the app in front, so that app receives the key
/// itself (games, virtual machines, remote desktops). Swoop's own windows never suspend it.
public enum ShortcutSuspension {
    public static func shouldSuspend(frontmostBundleID: String?, ownBundleID: String?, ignored: AppList) -> Bool {
        guard let front = frontmostBundleID else { return false }
        if let own = ownBundleID, front.caseInsensitiveCompare(own) == .orderedSame { return false }
        return ignored.contains(front)
    }
}
