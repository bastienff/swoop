#if DEBUG
import AppKit

/// Test actions shared by Settings → Debug and the menu-bar Debug submenu (DEBUG builds only).
@MainActor
enum DebugActions {
    static var bundleID: String { Bundle.main.bundleIdentifier ?? "com.bastienff.swoop" }

    /// `tccutil reset Accessibility <bundle id>`, mark onboarding not done, then relaunch or quit.
    /// Returns an error message, or nil if the app is relaunching/quitting.
    @discardableResult
    static func resetAccessibility(_ c: AppController, relaunch shouldRelaunch: Bool) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p.arguments = ["reset", "Accessibility", bundleID]
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return "tccutil failed: \(error.localizedDescription)"
        }
        guard p.terminationStatus == 0 else { return "tccutil exited with \(p.terminationStatus)." }
        c.settings.onboardingCompleted = false
        if shouldRelaunch { relaunch() } else { NSApp.terminate(nil) }
        return nil
    }

    /// Starts a fresh copy through LaunchServices (`open`, so TCC attributes it to the app), then quits.
    static func relaunch() {
        UserDefaults.standard.synchronize()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.7; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? p.run()
        NSApp.terminate(nil)
    }

    static func resetAllSettingsAndRelaunch() {
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        relaunch()
    }

    static func openRegistryDump(_ c: AppController) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("swoop-registry.txt")
        try? c.registry.dump().write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(url)
    }

    static func revealDataFolder() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Swoop")
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }

    static func showTestHUD(_ c: AppController) {
        c.hud.show("Couldn't reach “Example — project” without moving it. Visit its desktop once so Swoop can learn where it is.")
    }

    /// The menu-bar Debug submenu.
    static func menu(_ c: AppController) -> NSMenu {
        let m = NSMenu(title: "Debug")
        func item(_ title: String, _ run: @escaping @MainActor () -> Void) {
            m.addItem(ClosureMenuItem(title: title, run))
        }
        func note(_ title: String) {
            let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            i.isEnabled = false
            m.addItem(i)
        }
        note("\(bundleID) · pid \(ProcessInfo.processInfo.processIdentifier)")
        note("\(c.registry.entries.count) windows · \(Int(c.registry.lastRefreshDuration * 1000)) ms\(c.registry.isDemo ? " · demo" : "")")
        m.addItem(.separator())
        item("Reset Accessibility & Relaunch") { resetAccessibility(c, relaunch: true) }
        item("Reset Accessibility & Quit") { resetAccessibility(c, relaunch: false) }
        item("Show Onboarding Window") { c.openOnboardingHandler?() }
        item("Reset Onboarding") { c.settings.onboardingCompleted = false }
        item("Show System Accessibility Prompt") { c.permissions.requestAccessibility() }
        m.addItem(.separator())
        item("Forget Anchors (simulate relaunch)") { c.registry.forgetAnchors() }
        item("Forget Remembered Windows") { c.registry.resetRecovery() }
        item("Refresh Now") { Task { await c.registry.refresh() } }
        item("Open Registry Dump") { openRegistryDump(c) }
        m.addItem(.separator())
        if c.registry.isDemo {
            item("Exit Demo") { Task { await c.registry.exitDemo() } }
        } else {
            item("Load Demo Windows") { DebugCommands.loadDemo(into: c.registry) }
        }
        item("Show Test HUD") { showTestHUD(c) }
        m.addItem(.separator())
        note("Support card: \(c.supportPrompt.debugSummary)")
        item("Show Support Card Now") { c.supportPrompt.show() }
        item("Make Support Card Due (next switch)") { c.supportPrompt.debugMakeDue() }
        item("Reset Support Card (fresh install)") { c.supportPrompt.debugReset() }
        m.addItem(.separator())
        item("Clear Recent Usage") { c.recents.reset() }
        item("Reveal Data Folder") { revealDataFolder() }
        item("Reset All Settings & Relaunch") { resetAllSettingsAndRelaunch() }
        item("Relaunch Swoop") { relaunch() }
        m.addItem(.separator())
        item("Open Debug Settings…") {
            c.openSettingsHandler?()
            c.selectSettingsPane?(SettingsPane.allCases.firstIndex(of: .debug) ?? 0)
        }
        return m
    }
}

/// Menu item that runs a closure (keeps the debug menu declarative).
@MainActor
final class ClosureMenuItem: NSMenuItem {
    private let run: @MainActor () -> Void

    init(title: String, _ run: @escaping @MainActor () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { MainActor.assumeIsolated { run() } }
}
#endif
