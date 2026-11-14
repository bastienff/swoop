import AppKit
import SwiftUI

/// Menu bar → Check for Updates… in the Swoop theme (Classic shows a standard alert instead).
/// Opens right away and follows the check live: checking → up to date / new version / couldn't check.
struct UpdateWindowView: View {
    let updates: UpdateChecker
    var close: () -> Void
    static let width: CGFloat = 340

    var body: some View {
        VStack(spacing: 0) {
            BrandIcon(size: 64, softInLight: true)
                .padding(.top, 40)
            content
                .padding(.horizontal, 28)
            Spacer(minLength: 0)
        }
        .frame(width: Self.width, height: 290)
        .background(BrandBackground(scale: 0.5).ignoresSafeArea())
        .animation(.easeOut(duration: 0.15), value: updates.status)
    }

    @ViewBuilder
    private var content: some View {
        switch updates.status {
        case .idle, .checking:
            header(String(localized: "Checking for updates…"),
                   String(localized: "Asking GitHub for the latest version."))
            ProgressView().controlSize(.small).padding(.top, 20)
        case .upToDate:
            header(String(localized: "Swoop is up to date"),
                   String(localized: "Version \(UpdateChecker.currentVersion) is the latest."),
                   symbol: "checkmark.circle.fill", color: .green)
            buttons { primary(String(localized: "OK"), action: close) }
        case .available(let version, let page):
            header(String(localized: "Swoop \(version) is available"),
                   String(localized: "You have \(UpdateChecker.currentVersion). Download the new version from GitHub, or run “brew upgrade” if you installed Swoop with Homebrew."),
                   symbol: "arrow.down.circle.fill", color: Brand.orange)
            buttons {
                Button(String(localized: "Later"), action: close)
                    .buttonStyle(BrandButtonStyle(prominent: false, height: 30))
                primary(String(localized: "Open Release Page")) { NSWorkspace.shared.open(page); close() }
            }
        case .failed(let message):
            header(String(localized: "Couldn't check for updates"), message,
                   symbol: "exclamationmark.triangle.fill", color: .orange)
            buttons {
                Button(String(localized: "Try Again")) { Task { await updates.check() } }
                    .buttonStyle(BrandButtonStyle(prominent: false, height: 30))
                primary(String(localized: "OK"), action: close)
            }
        }
    }

    private func header(_ title: String, _ message: String, symbol: String? = nil, color: Color = .secondary) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).foregroundStyle(color) }
                Text(title).font(.system(size: 17, weight: .bold))
            }
            .padding(.top, 14)
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func buttons(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 8) { content() }
            .focusEffectDisabled()
            .padding(.top, 20)
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(BrandButtonStyle(softInLight: true, height: 30))
            .keyboardShortcut(.defaultAction)
    }
}
