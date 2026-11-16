import AppKit
import SwiftUI

/// About window in the Swoop theme. The Classic theme keeps the standard
/// macOS About panel (`MenuBarController.showStandardAbout`).
struct AboutView: View {
    let updates: UpdateChecker
    static let size = CGSize(width: 340, height: 390)

    var body: some View {
        VStack(spacing: 0) {
            BrandIcon(size: 84, softInLight: true)
                .padding(.top, 46)
            Text(verbatim: "Swoop")
                .font(.system(size: 24, weight: .bold))
                .padding(.top, 12)
            Text("Version \(AppLinks.appVersion)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 2)
            UpdateStatusView(checker: updates, centered: true)
                .environment(\.themeAccent, Brand.orange)
                .padding(.top, 6)
            Text("Just a window switcher. Window\ninformation never leaves this Mac.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
            HStack(spacing: 8) {
                Button("Sponsor Swoop") { NSWorkspace.shared.open(AppLinks.sponsor) }
                    .buttonStyle(BrandButtonStyle(softInLight: true, height: 30))
                Button("Star on GitHub") { NSWorkspace.shared.open(AppLinks.repository) }
                    .buttonStyle(BrandButtonStyle(prominent: false, height: 30))
            }
            .focusEffectDisabled()
            .padding(.top, 20)
            HStack(spacing: 14) {
                link("Website", AppLinks.repository)
                link("Release notes", AppLinks.repository.appendingPathComponent("releases"))
                link("MIT License", AppLinks.repository.appendingPathComponent("blob/main/LICENSE"))
            }
            .padding(.top, 18)
            Spacer(minLength: 0)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(FrostedBrandBackground(scale: 0.5).ignoresSafeArea())
    }

    private func link(_ title: LocalizedStringKey, _ url: URL) -> some View {
        Button(title) { NSWorkspace.shared.open(url) }
            .buttonStyle(.plain)
            .font(.system(size: 11.5))
            .foregroundStyle(Brand.orange)
            .onHover { inside in if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
    }
}
