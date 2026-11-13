#if DEBUG
import AppKit
import ApplicationServices
import SwiftUI
import SwoopCore

/// Settings → Debug (DEBUG builds only): state at a glance and the actions needed to test a build
/// end to end — first run, permissions, recovery after restarts, demo data, panel and HUD.
struct DebugSettings: View {
    let controller: AppController
    @State private var status = ""
    @State private var tick = 0 // bumps to re-read non-observed state

    private var bundleID: String { DebugActions.bundleID }

    var body: some View {
        Form {
            Section("Build") {
                info("Version", "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") (Debug)")
                info("Bundle", bundleID)
                info("Path", Bundle.main.bundlePath)
                info("Process", "pid \(ProcessInfo.processInfo.processIdentifier)")
                info("Accessibility", controller.permissions.isAccessibilityTrusted ? "Granted" : "Not granted")
                info("Onboarding completed", controller.settings.onboardingCompleted ? "Yes" : "No")
                info("Shortcut", "\(controller.settings.effectiveShortcut?.displayString ?? "none")\(controller.shortcutError.map { " — \($0)" } ?? "")")
                info("Windows", "\(controller.registry.entries.count) entries, last full refresh \(Int(controller.registry.lastRefreshDuration * 1000)) ms\(controller.registry.isDemo ? " (demo)" : "")")
                info("Recovery", recoveryInfo)
                    .id(tick)
            }

            Section {
                action("Reset Accessibility & Relaunch", destructive: true) { resetAccessibility(relaunch: true) }
                action("Reset Accessibility & Quit", destructive: true) { resetAccessibility(relaunch: false) }
                action("Show Onboarding Window") { controller.openOnboardingHandler?() }
                action("Reset Onboarding (shows on next launch)") {
                    controller.settings.onboardingCompleted = false
                    report("Onboarding will show on next launch.")
                }
                action("Show System Accessibility Prompt") {
                    controller.permissions.requestAccessibility()
                    report("Prompt requested (macOS shows it only while access isn't granted).")
                }
                action("Open Accessibility Settings") { controller.permissions.openAccessibilitySettings() }
            } header: {
                Text("First Run & Permissions")
            } footer: {
                footnote("Reset runs `tccutil reset Accessibility \(bundleID)`. After relaunch Swoop behaves like a first install.")
            }

            Section {
                action("Forget Anchors (simulate relaunch)") {
                    controller.registry.forgetAnchors()
                    report("In-memory anchors dropped; remembered ids kept. Open the switcher to test recovery.")
                }
                action("Forget Remembered Windows") {
                    controller.registry.resetRecovery()
                    report("Remembered window ids and sweep cursors cleared.")
                }
                action("Refresh Now") {
                    Task { await controller.registry.refresh(); report("Refreshed: \(controller.registry.entries.count) windows.") }
                }
                action("Open Registry Dump") { DebugActions.openRegistryDump(controller) }
            } header: {
                Text("Window Discovery")
            } footer: {
                footnote("Forget Anchors tests recovery without restarting; Forget Remembered Windows makes the next restart rely on the background sweep only.")
            }

            Section("Demo & UI") {
                if controller.registry.isDemo {
                    action("Exit Demo (resume real windows)") {
                        Task { await controller.registry.exitDemo(); report("Back to real windows.") }
                    }
                } else {
                    action("Load Demo Windows") {
                        DebugCommands.loadDemo(into: controller.registry)
                        report("Demo windows loaded; discovery paused. Open the switcher (README screenshots).")
                    }
                }
                action("Show Switcher") { controller.showPanel() }
                action("Show Test HUD") { DebugActions.showTestHUD(controller) }
            }

            Section {
                info("State", controller.supportPrompt.debugSummary).id(tick)
                action("Show Support Card Now") { controller.supportPrompt.show() }
                action("Make Due (shows after next switch)") {
                    controller.supportPrompt.debugMakeDue(); report("Support card will show after the next successful switch.")
                }
                action("Reset (fresh install)") {
                    controller.supportPrompt.debugReset(); report("Support card reset.")
                }
            } header: {
                Text("Support Card")
            } footer: {
                footnote("First card after \(SupportPromptPolicy.firstPromptSwitches) switches or 2 days (with ≥ \(SupportPromptPolicy.minimumSwitches) switches), whichever comes first. Coffee/star or \"Don't ask again\" stops it for good; ✕ / Maybe later / ignoring it postpones 2 days.")
            }

            Section("Data") {
                action("Clear Recent Usage") { controller.recents.reset(); report("Recent usage cleared.") }
                action("Reveal Data Folder") { DebugActions.revealDataFolder() }
                action("Reset All Settings & Relaunch", destructive: true) { DebugActions.resetAllSettingsAndRelaunch() }
            }

            Section {
                action("Relaunch Swoop") { DebugActions.relaunch() }
                action("Quit Swoop", destructive: true) { NSApp.terminate(nil) }
                if !status.isEmpty { footnote(status) }
            }
        }
        .formStyle(.grouped)
        // Taller than a laptop screen if laid out in full: fixed height, the form scrolls.
        .frame(height: 620)
        .onAppear { controller.permissions.refresh(); tick += 1 }
    }

    // MARK: - Actions

    private func resetAccessibility(relaunch shouldRelaunch: Bool) {
        if let error = DebugActions.resetAccessibility(controller, relaunch: shouldRelaunch) { report(error) }
    }

    private var recoveryInfo: String {
        guard RemoteElements.isAvailable else { return "Unavailable (private symbols missing)" }
        guard controller.settings.recoverOtherSpaceWindows else { return "Off in Behavior" }
        let s = controller.registry.recoveryStats
        return "On — \(s?.ids ?? 0) ids for \(s?.apps ?? 0) apps, \(controller.registry.anchorCount) anchors"
    }

    private func report(_ s: String) { status = s; tick += 1 }

    // MARK: - Rows

    private func info(_ label: String, _ value: String) -> some View {
        LabeledContent(label) { Text(value).textSelection(.enabled).multilineTextAlignment(.trailing) }
    }

    private func action(_ title: String, destructive: Bool = false, _ run: @escaping () -> Void) -> some View {
        Button(title, role: destructive ? .destructive : nil, action: run)
    }

    private func footnote(_ s: String) -> some View {
        Text(s).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
#endif
