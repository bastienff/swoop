import AppKit
import Observation
import SwoopCore

enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { switch self { case .system: String(localized: "Follow System"); case .light: String(localized: "Light"); case .dark: String(localized: "Dark") } }
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Overall look. Classic is the original look and the default; Swoop applies
/// the onboarding's brand look to the switcher, Settings, About and the support card.
enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case swoop, classic
    var id: String { rawValue }
    var label: String { self == .swoop ? "Swoop" : String(localized: "Classic", comment: "Theme name") }
}

enum IconSize: String, CaseIterable, Identifiable, Sendable {
    case small, medium, large
    var id: String { rawValue }
    var label: String {
        switch self {
        case .small: String(localized: "Small", comment: "Icon size")
        case .medium: String(localized: "Medium", comment: "Icon size")
        case .large: String(localized: "Large", comment: "Icon size")
        }
    }
    var points: Double { switch self { case .small: 64; case .medium: 80; case .large: 96 } }
}

/// How results are shown: the icon grid, or a list with one- or two-line rows.
enum PanelLayout: String, CaseIterable, Identifiable, Sendable {
    case grid, compactList, comfortableList
    var id: String { rawValue }
    var label: String {
        switch self {
        case .grid: String(localized: "Grid")
        case .compactList: String(localized: "List · Compact")
        case .comfortableList: String(localized: "List · Comfortable")
        }
    }
    var isList: Bool { self != .grid }
}

enum PanelDisplay: String, CaseIterable, Identifiable, Sendable {
    case activeWindow, mouseCursor, primary
    var id: String { rawValue }
    var label: String {
        switch self {
        case .activeWindow: String(localized: "Display with the active window")
        case .mouseCursor: String(localized: "Display with the mouse cursor")
        case .primary: String(localized: "Primary display")
        }
    }
}

extension WindowOrder {
    var label: String {
        switch self {
        case .smart: String(localized: "Smart", comment: "Window order")
        case .recent: String(localized: "Recent use")
        case .name: String(localized: "Name", comment: "Window order: alphabetical")
        }
    }
    var explanation: String {
        switch self {
        case .smart: String(localized: "Most recently used first, but the window you're in comes second, so the window you came from is selected: open Swoop and press Return to go back.")
        case .recent: String(localized: "Most recently used first, starting with the window you're in.")
        case .name: String(localized: "Alphabetical by app, then by window title.")
        }
    }
}

/// What happens when the shortcut's modifier key is released.
enum SwitcherMode: String, CaseIterable, Identifiable, Sendable {
    /// The switcher stays open until you pick a window or dismiss it (PRD §3 default).
    case stayOpen
    /// Like macOS ⌘Tab: hold the modifier, press the key to cycle, release to switch.
    case switchOnRelease
    var id: String { rawValue }
    var label: String {
        switch self {
        case .stayOpen: String(localized: "Keep the switcher open")
        case .switchOnRelease: String(localized: "Switch to the selected window")
        }
    }
}

extension UpdatePolicy.Frequency: Identifiable {
    public var id: String { rawValue }
    var label: String {
        switch self {
        case .daily: String(localized: "Daily", comment: "Update check frequency")
        case .weekly: String(localized: "Weekly", comment: "Update check frequency")
        case .monthly: String(localized: "Monthly", comment: "Update check frequency")
        }
    }
}

/// User preferences persisted in `UserDefaults`.
@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    var shortcutEnabled: Bool { didSet { save("shortcutEnabled", shortcutEnabled) } }
    var shortcut: Shortcut { didSet { saveCodable("shortcut", shortcut) } }
    /// Must be explicitly enabled before an unmodified Tab can be recorded/registered.
    var allowBareTab: Bool { didSet { save("allowBareTab", allowBareTab) } }
    var switcherMode: SwitcherMode { didSet { save("switcherMode", switcherMode.rawValue) } }

    var theme: AppTheme { didSet { save("theme", theme.rawValue) } }
    var appearance: AppearanceMode { didSet { save("appearance", appearance.rawValue) } }
    var iconSize: IconSize { didSet { save("iconSize", iconSize.rawValue) } }
    var maxVisibleRows: Int { didSet { save("maxVisibleRows", maxVisibleRows) } }
    var panelLayout: PanelLayout { didSet { save("panelLayout", panelLayout.rawValue) } }
    /// Visible rows in the list layouts before the list scrolls.
    var maxVisibleListRows: Int { didSet { save("maxVisibleListRows", maxVisibleListRows) } }
    var panelDisplay: PanelDisplay { didSet { save("panelDisplay", panelDisplay.rawValue) } }
    /// Off: the switcher is always centered. On: it can be dragged and reopens where it was left (per display).
    var panelDraggable: Bool { didSet { save("panelDraggable", panelDraggable) } }
    /// Where the switcher was left on each display: its center as fractions (0…1) of the display's visible area.
    private(set) var panelPositions: [String: [Double]] { didSet { save("panelPositions", panelPositions) } }

    func panelCenter(display: String) -> CGPoint? {
        guard let p = panelPositions[display], p.count == 2 else { return nil }
        return CGPoint(x: p[0], y: p[1])
    }

    func setPanelCenter(_ point: CGPoint, display: String) {
        panelPositions[display] = [min(max(point.x, 0), 1), min(max(point.y, 0), 1)]
    }

    func resetPanelPositions() { panelPositions = [:] }
    var alwaysShowSearchField: Bool { didSet { save("alwaysShowSearchField", alwaysShowSearchField) } }

    var dismissOnOutsideClick: Bool { didSet { save("dismissOnOutsideClick", dismissOnOutsideClick) } }
    var showMinimized: Bool { didSet { save("showMinimized", showMinimized) } }
    var includeFullScreen: Bool { didSet { save("includeFullScreen", includeFullScreen) } }
    var vscodeEnhancements: Bool { didSet { save("vscodeEnhancements", vscodeEnhancements) } }
    var nativeTabDiscovery: Bool { didSet { save("nativeTabDiscovery", nativeTabDiscovery) } }
    /// Recover windows on other desktops through private Accessibility SPI (§2a). Off → public APIs only.
    var recoverOtherSpaceWindows: Bool { didSet { save("recoverOtherSpaceWindows", recoverOtherSpaceWindows) } }
    var vscodeSearchBoost: Bool { didSet { save("vscodeSearchBoost", vscodeSearchBoost) } }
    var windowOrder: WindowOrder { didSet { save("windowOrder", windowOrder.rawValue) } }
    var debugLogging: Bool { didSet { save("debugLogging", debugLogging) } }
    /// Diagnostics reports include window titles only when this is on.
    var diagnosticsIncludeTitles: Bool { didSet { save("diagnosticsIncludeTitles", diagnosticsIncludeTitles) } }
    var onboardingCompleted: Bool { didSet { save("onboardingCompleted", onboardingCompleted) } }
    /// Automatic update check (one request to GitHub per interval). Off by default: no network without consent.
    var checkForUpdates: Bool { didSet { save("checkForUpdates", checkForUpdates) } }
    var updateFrequency: UpdatePolicy.Frequency { didSet { save("updateFrequency", updateFrequency.rawValue) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func b(_ k: String, _ d: Bool) -> Bool { defaults.object(forKey: k) as? Bool ?? d }
        shortcutEnabled = b("shortcutEnabled", true)
        shortcut = (defaults.data(forKey: "shortcut")).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? .default
        allowBareTab = b("allowBareTab", false)
        switcherMode = SwitcherMode(rawValue: defaults.string(forKey: "switcherMode") ?? "") ?? .stayOpen
        theme = AppTheme(rawValue: defaults.string(forKey: "theme") ?? "") ?? .classic
        appearance = AppearanceMode(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        iconSize = IconSize(rawValue: defaults.string(forKey: "iconSize") ?? "") ?? .large
        maxVisibleRows = defaults.object(forKey: "maxVisibleRows") as? Int ?? 4
        panelLayout = PanelLayout(rawValue: defaults.string(forKey: "panelLayout") ?? "") ?? .grid
        maxVisibleListRows = defaults.object(forKey: "maxVisibleListRows") as? Int ?? 9
        panelDisplay = PanelDisplay(rawValue: defaults.string(forKey: "panelDisplay") ?? "") ?? .activeWindow
        panelDraggable = b("panelDraggable", false)
        panelPositions = defaults.dictionary(forKey: "panelPositions") as? [String: [Double]] ?? [:]
        alwaysShowSearchField = b("alwaysShowSearchField", true)
        dismissOnOutsideClick = b("dismissOnOutsideClick", true)
        showMinimized = b("showMinimized", true)
        includeFullScreen = b("includeFullScreen", true)
        vscodeEnhancements = b("vscodeEnhancements", true)
        nativeTabDiscovery = b("nativeTabDiscovery", true)
        recoverOtherSpaceWindows = b("recoverOtherSpaceWindows", true)
        vscodeSearchBoost = b("vscodeSearchBoost", true)
        // Migrates the old "Sort by recent usage" toggle: off → by name; otherwise smart.
        windowOrder = WindowOrder(rawValue: defaults.string(forKey: "windowOrder") ?? "")
            ?? (b("sortByRecent", true) ? .smart : .name)
        debugLogging = b("debugLogging", false)
        diagnosticsIncludeTitles = b("diagnosticsIncludeTitles", false)
        onboardingCompleted = b("onboardingCompleted", false)
        checkForUpdates = b("checkForUpdates", false)
        updateFrequency = UpdatePolicy.Frequency(rawValue: defaults.string(forKey: "updateFrequency") ?? "") ?? .weekly
    }

    /// Shortcut to register, or nil if disabled or a bare Tab without opt-in.
    var effectiveShortcut: Shortcut? {
        guard shortcutEnabled else { return nil }
        if shortcut.isUnmodified && !allowBareTab { return nil }
        return shortcut
    }

    private func save(_ key: String, _ value: Any) { defaults.set(value, forKey: key) }
    private func saveCodable<T: Encodable>(_ key: String, _ value: T) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
