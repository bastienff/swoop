import Foundation

/// How a window entry was discovered. Higher raw value = more precise / safer to activate.
public enum WindowSource: Int, Sendable, Comparable, Codable {
    /// Seen only as a Window-menu item (`makeKeyAndOrderFront:`), typically on another Space.
    case menuOnly = 0
    /// The app's main/focused window element (available even when on another Space).
    case mainOrFocused = 1
    /// A non-selected native tab inside a known tab group.
    case tab = 2
    /// A visible window element learned on a previously visited Space.
    case anchor = 3
    /// A window element visible on the current Space (or minimized).
    case visible = 4

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// Normalized, UI-facing description of one selectable window or native tab.
public struct WindowEntry: Sendable, Identifiable, Hashable {
    public var id: String
    public var pid: Int32
    public var bundleID: String?
    public var appName: String
    public var title: String
    /// VS Code (or similar) project/workspace name when reliably parsed.
    public var projectName: String?
    /// Secondary detail, e.g. the active file in a VS Code window.
    public var detail: String?
    public var source: WindowSource
    public var isMinimized: Bool
    public var isFullScreen: Bool
    /// True when the window is believed to be on the current Space.
    public var isOnCurrentSpace: Bool
    public var isNativeTab: Bool
    public var lastUsed: Date?

    public init(
        id: String, pid: Int32, bundleID: String?, appName: String, title: String,
        projectName: String? = nil, detail: String? = nil, source: WindowSource,
        isMinimized: Bool = false, isFullScreen: Bool = false, isOnCurrentSpace: Bool = false,
        isNativeTab: Bool = false, lastUsed: Date? = nil
    ) {
        self.id = id; self.pid = pid; self.bundleID = bundleID; self.appName = appName
        self.title = title; self.projectName = projectName; self.detail = detail; self.source = source
        self.isMinimized = isMinimized; self.isFullScreen = isFullScreen
        self.isOnCurrentSpace = isOnCurrentSpace; self.isNativeTab = isNativeTab; self.lastUsed = lastUsed
    }

    /// Key used to persist recent usage across launches (pids and AX elements don't survive).
    public var recencyKey: String { RecentUsage.key(bundleID: bundleID ?? appName, title: title) }

    /// Text shown under the app name.
    public var subtitle: String {
        if let projectName {
            if let detail, !detail.isEmpty { return "\(projectName) · \(detail)" }
            return projectName
        }
        return title
    }
}
