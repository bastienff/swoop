import AppKit
import ApplicationServices
import Observation

/// Accessibility permission state. Input Monitoring and Screen Recording are not needed
/// (ARCHITECTURE F13), so they are only reported, never requested.
@MainActor
@Observable
final class PermissionManager {
    private(set) var isAccessibilityTrusted = AXIsProcessTrusted()
    private var pollTask: Task<Void, Never>?
    var onChange: ((Bool) -> Void)?

    /// Shows the system prompt (once per app identity; macOS suppresses repeats).
    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        update(AXIsProcessTrustedWithOptions(options))
    }

    func refresh() { update(AXIsProcessTrusted()) }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// Polls only while something (onboarding/settings) is waiting for a change. No idle polling.
    func startWatching() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.refresh()
            }
        }
    }

    func stopWatching() { pollTask?.cancel(); pollTask = nil }

    private func update(_ trusted: Bool) {
        guard trusted != isAccessibilityTrusted else { return }
        isAccessibilityTrusted = trusted
        onChange?(trusted)
    }
}
