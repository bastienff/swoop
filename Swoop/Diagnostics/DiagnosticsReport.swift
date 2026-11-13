import AppKit
import OSLog

/// A plain-text report to attach to bug reports: version, system, status, settings, displays, the window
/// list and this session's Swoop log. Saved to ~/Library/Logs/Swoop and revealed in Finder.
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
        line("Session started: \(c.launchedAt.formatted(date: .abbreviated, time: .standard)) (the log covers this session only)")
        line("Window titles: \(titles ? "included" : "hidden")")

        section("Status")
        line("Accessibility: \(c.permissions.isAccessibilityTrusted ? "granted" : "NOT granted")")
        line("Shortcut: \(s.shortcutEnabled ? s.shortcut.displayString : "disabled")"
             + (s.effectiveShortcut == nil && s.shortcutEnabled ? " (inactive: bare key without opt-in)" : "")
             + (c.shortcutError.map { " — error: \($0)" } ?? ""))
        line("Launch at login: \(LaunchAtLogin.isEnabled)")

        section("Settings")
        line("release behavior=\(s.switcherMode.rawValue), window order=\(s.windowOrder.rawValue), allow bare Tab=\(s.allowBareTab)")
        line("layout=\(s.panelLayout.rawValue), icon size=\(s.iconSize.rawValue), max rows=\(s.maxVisibleRows)/\(s.maxVisibleListRows) (grid/list)")
        line("appearance=\(s.appearance.rawValue), display=\(s.panelDisplay.rawValue), draggable=\(s.panelDraggable), always show search=\(s.alwaysShowSearchField)")
        line("dismiss on outside click=\(s.dismissOnOutsideClick), show minimized=\(s.showMinimized), include full screen=\(s.includeFullScreen)")
        line("native tabs=\(s.nativeTabDiscovery), remember other desktops=\(s.recoverOtherSpaceWindows), VS Code names=\(s.vscodeEnhancements), VS Code boost=\(s.vscodeSearchBoost)")
        line("debug logging=\(s.debugLogging)")

        section("Displays")
        for (i, screen) in NSScreen.screens.enumerated() {
            let f = screen.frame
            line("\(i == 0 ? "primary" : "display \(i + 1)"): \(Int(f.width))×\(Int(f.height)) pt @\(Int(screen.backingScaleFactor))x")
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
