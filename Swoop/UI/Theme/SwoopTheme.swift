import AppKit
import SwiftUI

/// The "Swoop" theme's building blocks: the onboarding's look, shared by the
/// switcher, Settings, About and the support card when Settings → Appearance → Theme is "Swoop".
/// The Classic theme never uses these, so it stays exactly as before.
enum Brand {
    /// The app icon's gradient.
    static let orange = Color(red: 0.95, green: 0.42, blue: 0.16)
    static let orangeLight = Color(red: 1.00, green: 0.58, blue: 0.24)
    static let violet = Color(red: 0.45, green: 0.36, blue: 0.95)
}

/// Warm brand glow over a soft wash; deep indigo in dark mode (like the demo wallpaper).
/// `scale` sizes the glows to the surface (1 ≈ an 800 pt window; smaller surfaces need smaller glows).
struct BrandBackground: View {
    var scale: CGFloat = 1
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            LinearGradient(colors: dark
                           ? [Color(red: 0.13, green: 0.10, blue: 0.21), Color(red: 0.08, green: 0.07, blue: 0.15)]
                           : [Color(red: 1.00, green: 0.96, blue: 0.93), Color(red: 0.95, green: 0.91, blue: 0.98)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Brand.orange.opacity(dark ? 0.30 : 0.28), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 520 * scale)
            RadialGradient(colors: [Brand.violet.opacity(dark ? 0.40 : 0.22), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 560 * scale)
        }
    }
}

/// `BrandBackground` with glows sized to whatever it fills (panels change size with their content).
struct FittedBrandBackground: View {
    var body: some View {
        GeometryReader { geo in
            BrandBackground(scale: max(geo.size.width, geo.size.height) / 800)
        }
    }
}

/// Capsule buttons in the brand colors. Unlike `.borderedProminent`, they keep their color when the
/// window isn't key (an accessory app's window often isn't, right after launch).
struct BrandButtonStyle: ButtonStyle {
    var prominent = true
    /// A subtler glow in light mode (About, support card); the onboarding keeps the full glow.
    var softInLight = false
    var height: CGFloat = 34
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        // One shape for fill, border and hit area, so they line up exactly at the rounded ends.
        let shape = RoundedRectangle(cornerRadius: height / 2, style: .circular)
        let soft = softInLight && scheme != .dark
        return configuration.label
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 18)
            .frame(height: height)
            .background(prominent
                        ? AnyShapeStyle(LinearGradient(colors: [Brand.orangeLight, Brand.orange], startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(Color.primary.opacity(scheme == .dark ? 0.12 : 0.07)),
                        in: shape)
            .overlay { if !prominent { shape.strokeBorder(Color.primary.opacity(0.08)) } }
            .shadow(color: Brand.orange.opacity(prominent ? (soft ? 0.16 : 0.35) : 0),
                    radius: prominent ? (soft ? 4 : 8) : 0, y: prominent ? (soft ? 2 : 3) : 0)
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The app icon with a soft orange glow behind it (a shadow on the image itself shows its square bounds).
struct BrandIcon: View {
    let size: CGFloat
    var softInLight = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(Brand.orange)
                    .frame(width: size * 0.72, height: size * 0.72)
                    .offset(y: size * 0.08)
                    .blur(radius: size * 0.2)
                    .opacity(softInLight && scheme != .dark ? 0.22 : 0.45))
            .accessibilityHidden(true)
    }
}

/// Selection color for Swoop's own controls (picture pickers): the system accent in Classic, brand orange
/// in the Swoop theme.
private struct ThemeAccentKey: EnvironmentKey {
    static let defaultValue = Color.accentColor
}

extension EnvironmentValues {
    var themeAccent: Color {
        get { self[ThemeAccentKey.self] }
        set { self[ThemeAccentKey.self] = newValue }
    }
}
