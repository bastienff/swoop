import AppKit
import OSLog

/// A plain-text report to attach to bug reports: version and install, status, what happened this session,
/// macOS settings and other apps that affect switching, Swoop's settings, displays, per-app discovery, the
/// window list and this session's Swoop log. Saved to ~/Library/Logs/Swoop and revealed in Finder.
///
/// Privacy: window titles are left out unless Settings → Advanced → "Include window titles" is on. The log
/// is read back through OSLogStore, where values Swoop logs as private (titles) are already `<private>`.
@MainActor
enum DiagnosticsReport {
    static let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Swoop", isDirectory: true)
    nonisolated static let maxLogEntries = 1500

    /// Writes a new report and returns its file URL.
    static func save(_ c: AppController) async throws -> URL {
        let text = await make(c)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd-HHmmss"
        let url = folder.appendingPathComponent("Swoop-diagnostics-\(stamp.string(from: Date())).txt")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func saveAndReveal(_ c: AppController) async -> URL? {
        do {
            let url = try await save(c)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return url
        } catch {
            c.hud.show("Couldn't save the diagnostics report: \(error.localizedDescription)")
            return nil
        }
    }

    static func make(_ c: AppController) async -> String {
        let s = c.settings
        let titles = s.diagnosticsIncludeTitles
        let log = await recentLog(includeRegistryDumps: titles)
        var r = ""
        func line(_ text: String = "") { r += text + "\n" }
        func section(_ title: String) { line(); line("== \(title)") }

        line("Swoop diagnostics report")
        line("Created: \(Date().formatted(date: .abbreviated, time: .standard))")
        line("Swoop \(AppLinks.appVersion) · \(AppLinks.systemDescription)")
        line("Session started: \(c.launchedAt.formatted(date: .abbreviated, time: .standard)), \(DiagnosticsInfo.duration(Date().timeIntervalSince(c.launchedAt))) ago (the log covers this session only)")
        line("Window titles: \(titles ? "included" : "hidden")")

        section("Install")
        DiagnosticsInfo.installLines.forEach { line($0) }

        section("Status")
        line("Accessibility: \(c.permissions.isAccessibilityTrusted ? "granted" : "NOT granted")")
        let shortcut = s.shortcutEnabled ? s.shortcut.displayString + " (key code \(s.shortcut.keyCode))" : "disabled"
        line("Shortcut: \(shortcut), registered: \(c.hotkeys.current != nil)"
             + (s.effectiveShortcut == nil && s.shortcutEnabled ? " (inactive: bare key without opt-in)" : "")
             + (c.shortcutError.map { " — error: \($0)" } ?? ""))
        line("Keyboard: \(DiagnosticsInfo.inputSources)")
        line("Secure keyboard entry: \(DiagnosticsInfo.secureInput)")
        line("Element recovery (other desktops): " + (RemoteElements.isAvailable
            ? "available, \(s.recoverOtherSpaceWindows ? "on" : "off")" + (c.registry.recoveryStats.map { ", remembers \($0.ids) windows in \($0.apps) apps" } ?? "")
            : "unavailable on this macOS (public fallback)") + ", learned anchors \(c.registry.anchorCount)")
        line("Swoop process: \(DiagnosticsInfo.processLine)")

        section("This session")
        let stats = SessionStats.shared
        line("Shortcut presses: \(stats.shortcutPresses), switcher opened: \(stats.panelOpens)"
             + (stats.blockedOpens > 0 ? ", blocked (no Accessibility): \(stats.blockedOpens)" : ""))
        line("Switches: " + (stats.outcomes.isEmpty ? "none" : stats.outcomes.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", ")))
        if !stats.focusTakers.isEmpty {
            line("Apps that took focus from the open switcher: " + stats.focusTakers.sorted { $0.value > $1.value }.map { "\($0.key) ×\($0.value)" }.joined(separator: ", "))
        }
        if !stats.recent.isEmpty {
            line("Recent switches (newest last):")
            let time = DateFormatter()
            time.dateFormat = "HH:mm:ss"
            for a in stats.recent { line("  \(time.string(from: a.at)) \(a.app) route=\(a.route) \(a.outcome) in \(a.milliseconds) ms") }
        }
        line("Full refresh: last \(c.registry.lastRefresh.map { "\(DiagnosticsInfo.duration(Date().timeIntervalSince($0))) ago" } ?? "never"), took \(Int(c.registry.lastRefreshDuration * 1000)) ms")

        section("macOS settings")
        DiagnosticsInfo.systemSettingLines.forEach { line($0) }

        section("Other apps that can affect shortcuts, windows or desktops")
        let related = DiagnosticsInfo.relatedApps
        line(related.isEmpty ? "none detected" : related.joined(separator: ", "))

        section("Settings")
        line("release behavior=\(s.switcherMode.rawValue), window order=\(s.windowOrder.rawValue), allow bare Tab=\(s.allowBareTab)")
        line("layout=\(s.panelLayout.rawValue), icon size=\(s.iconSize.rawValue), max rows=\(s.maxVisibleRows)/\(s.maxVisibleListRows) (grid/list)")
        line("theme=\(s.theme.rawValue), appearance=\(s.appearance.rawValue), display=\(s.panelDisplay.rawValue), draggable=\(s.panelDraggable), always show search=\(s.alwaysShowSearchField)")
        line("dismiss on outside click=\(s.dismissOnOutsideClick), show minimized=\(s.showMinimized), include full screen=\(s.includeFullScreen)")
        line("hidden apps=\(s.hiddenApps.isEmpty ? "none" : s.hiddenApps.apps.map(\.bundleID).joined(separator: ", "))")
        line("shortcut ignored in=\(s.shortcutIgnoredApps.isEmpty ? "none" : s.shortcutIgnoredApps.apps.map(\.bundleID).joined(separator: ", ")), released now=\(c.shortcutSuspended)")
        line("native tabs=\(s.nativeTabDiscovery), remember other desktops=\(s.recoverOtherSpaceWindows), VS Code names=\(s.vscodeEnhancements), VS Code boost=\(s.vscodeSearchBoost)")
        line("update checks=\(s.checkForUpdates ? s.updateFrequency.rawValue : "manual"), onboarding completed=\(s.onboardingCompleted), debug logging=\(s.debugLogging)")

        section("Displays")
        let menuBarScreen = NSScreen.screens.first
        for (i, screen) in NSScreen.screens.enumerated() {
            let f = screen.frame, v = screen.visibleFrame
            var d = "\(i + 1). \(screen.localizedName): \(Int(f.width))×\(Int(f.height)) pt at (\(Int(f.minX)), \(Int(f.minY))) @\(Int(screen.backingScaleFactor))x"
            d += ", usable \(Int(v.width))×\(Int(v.height))"
            if screen == menuBarScreen { d += ", primary" }
            if screen == NSScreen.main { d += ", active" }
            line(d)
        }

        let census = WindowCensus.current()
        section("Apps (front to back)")
        let apps = c.registry.appDiagnostics(census: census, observed: c.observers.observedPIDs)
        if apps.isEmpty { line("(none discovered)") }
        apps.forEach { line($0) }
        // Apps with real windows that Swoop doesn't list (menu-bar/background apps aren't "regular" apps).
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let discovered = c.registry.discoveredPIDs
        let unlisted = census.frames.keys.filter { $0 != ownPID && !discovered.contains($0) }.compactMap { pid -> String? in
            // Background helpers (AutoFill, open/save panels) and the login window are never switch targets.
            guard let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy != .prohibited,
                  app.bundleIdentifier != "com.apple.loginwindow" else { return nil }
            let policy = app.activationPolicy == .regular ? "regular app, not discovered yet" : "menu-bar app"
            return "\(app.localizedName ?? "?") [\(app.bundleIdentifier ?? "no bundle id")]: \(census.windowCount(pid)) windows, \(policy)"
        }.sorted()
        if !unlisted.isEmpty {
            line("Not listed by Swoop (has windows, but Swoop only lists regular apps):")
            unlisted.forEach { line("  " + $0) }
        }

        section("Windows")
        r += c.registry.dump(includeTitles: titles)

        section("Log (this session, newest last)")
        r += log.isEmpty ? "(no entries)\n" : log.joined(separator: "\n") + "\n"
        return r
    }

    /// This process's Swoop log entries (info and above; debug isn't retained by macOS).
    private static func recentLog(includeRegistryDumps: Bool) async -> [String] {
        await Task.detached(priority: .userInitiated) {
            do {
                let store = try OSLogStore(scope: .currentProcessIdentifier)
                let entries = try store.getEntries(matching: NSPredicate(format: "subsystem == %@", "com.bastienff.swoop"))
                let time = DateFormatter()
                time.dateFormat = "HH:mm:ss.SSS"
                var lines: [String] = []
                for case let e as OSLogEntryLog in entries {
                    // Debug-logging registry dumps are logged publicly (with titles): only include them on opt-in.
                    if !includeRegistryDumps && e.category == "registry" && e.composedMessage.hasPrefix("Registry @") { continue }
                    let level = switch e.level {
                    case .error: "ERROR"
                    case .fault: "FAULT"
                    case .notice: "notice"
                    default: "info"
                    }
                    lines.append("\(time.string(from: e.date)) [\(e.category)] \(level): \(e.composedMessage)")
                }
                return Array(lines.suffix(maxLogEntries))
            } catch {
                return ["(couldn't read the log: \(error.localizedDescription))"]
            }
        }.value
    }
}
