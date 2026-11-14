import AppKit
import SwiftUI

/// "Check for Updates" button and the result of the last check, used in Settings and About.
/// Before a check: the button. While checking: a spinner. Then an icon + one line:
/// ✓ up to date, ↓ new version (with a link to its release page), ⚠ couldn't check (with Try Again).
struct UpdateStatusView: View {
    let checker: UpdateChecker
    /// About: centered and compact. Settings: leading-aligned, as a form row.
    var centered = false
    @Environment(\.themeAccent) private var accent

    var body: some View {
        HStack(spacing: 6) {
            switch checker.status {
            case .idle:
                checkButton(String(localized: "Check for Updates"))
            case .checking:
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundStyle(.secondary)
            case .upToDate:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Swoop is up to date")
                checkButton(String(localized: "Check Again"), subtle: true)
            case .available(let version, let page):
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(accent)
                Text("Version \(version) is available")
                styled(Button(String(localized: "Download")) { NSWorkspace.shared.open(page) }, link: centered)
                    .help(page.absoluteString)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Couldn't check for updates").help(message)
                checkButton(String(localized: "Try Again"), subtle: true)
            }
        }
        .lineLimit(1)
        .fixedSize() // full text; a form row's value column would otherwise truncate it
        .font(centered ? .system(size: 11.5) : .body)
        .frame(maxWidth: centered ? .infinity : nil, alignment: centered ? .center : .leading)
        .animation(.easeOut(duration: 0.15), value: checker.status)
        .accessibilityElement(children: .contain)
    }

    private func checkButton(_ title: String, subtle: Bool = false) -> some View {
        styled(Button(title) { Task { await checker.check() } }, link: subtle || centered)
    }

    /// About uses text links (like its other links, in the accent color); Settings uses a regular button.
    @ViewBuilder
    private func styled(_ button: some View, link: Bool) -> some View {
        if link { button.buttonStyle(.link).foregroundStyle(centered ? accent : Color.accentColor) } else { button }
    }
}
