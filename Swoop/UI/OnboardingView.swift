import SwiftUI
import SwoopCore

/// First-run / missing-permission window (PRD §11). Polls trust only while visible.
struct OnboardingView: View {
    let controller: AppController
    var onDone: () -> Void

    var body: some View {
        let p = controller.permissions
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to Swoop").font(.title.bold())
                    Text("Press \(controller.settings.effectiveShortcut?.displayString ?? Shortcut.default.displayString) anywhere to see every window, search, and jump to it — even on other desktops.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    PermissionRow(title: "Accessibility", granted: p.isAccessibilityTrusted, required: true,
                                  detail: "Swoop needs Accessibility to list windows of other apps, read their titles and native tabs (like VS Code projects), and focus the exact window you choose. Window information stays on this Mac.")
                    if !p.isAccessibilityTrusted {
                        HStack {
                            Button("Request Access") { p.requestAccessibility() }
                                .keyboardShortcut(.defaultAction)
                            Button("Open System Settings") { p.openAccessibilitySettings() }
                        }
                        Text("In System Settings → Privacy & Security → Accessibility, turn on “Swoop”. This window updates automatically; no restart is needed. If the switch is already on but this still says “Not granted”, turn it off and on again.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Label("All set — \(controller.registry.entries.count) windows found.", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                }
                .padding(6)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Not needed").font(.headline)
                Text("• Input Monitoring — the shortcut uses a standard hotkey that doesn't read your typing.\n• Screen Recording — Swoop shows app icons, not window previews.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(p.isAccessibilityTrusted ? "Done" : "Later") { onDone() }
                    .keyboardShortcut(p.isAccessibilityTrusted ? .defaultAction : .cancelAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear { p.refresh(); p.startWatching() }
        .onDisappear { p.stopWatching() }
    }
}
