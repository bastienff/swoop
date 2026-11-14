import AppKit
import SwiftUI
import SwoopCore

/// Guided first-run setup (PRD §11): welcome → permissions → shortcut → look → support → done.
/// Shown once; afterwards, a missing Accessibility grant reopens only the permissions step.
@MainActor
@Observable
final class OnboardingModel {
    enum Step: Int, CaseIterable { case welcome, permissions, shortcut, look, support, done }

    private(set) var steps: [Step]
    private(set) var index = 0
    /// Direction of the last move, for the slide transition.
    private(set) var forward = true
    /// The coffee/star links were used (shows the thank-you state).
    var supported = false
    #if DEBUG
    /// Debug: show the "not granted" state on a Mac that already granted Accessibility.
    var previewNotGranted = false
    #endif

    func isTrusted(_ permissions: PermissionManager) -> Bool {
        #if DEBUG
        if previewNotGranted { return false }
        #endif
        return permissions.isAccessibilityTrusted
    }

    var step: Step { steps[index] }
    var isPermissionsOnly: Bool { steps == [.permissions] }
    var isFirst: Bool { index == 0 }
    var isLast: Bool { index == steps.count - 1 }

    init(permissionsOnly: Bool) {
        steps = permissionsOnly ? [.permissions] : Step.allCases
    }

    func next() { go(to: index + 1) }
    func back() { go(to: index - 1) }

    func go(to i: Int) {
        guard steps.indices.contains(i), i != index else { return }
        forward = i > index
        index = i
    }

    /// "Skip setup" without Accessibility: only the permissions step remains.
    func skipToPermissions() {
        forward = true
        steps = [.permissions]
        index = 0
    }
}

struct OnboardingView: View {
    let controller: AppController
    @Bindable var model: OnboardingModel
    /// Finish setup; `openSwoop` shows the switcher right away ("Swoop away").
    var onFinish: (_ openSwoop: Bool) -> Void

    @State private var window: NSWindow?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let size = CGSize(width: 800, height: 590)
    static let topInset: CGFloat = 50
    static let footerHeight: CGFloat = 76

    var body: some View {
        let p = controller.permissions
        ZStack {
            BrandBackground().ignoresSafeArea()
            Group {
                switch model.step {
                case .welcome: WelcomeStep(shortcut: shortcutDisplay)
                case .permissions: PermissionsStep(controller: controller, granted: model.isTrusted(p))
                case .shortcut: ShortcutStep(controller: controller)
                case .look: LookStep(settings: controller.settings)
                case .support: SupportStep(controller: controller, model: model)
                case .done: DoneStep(shortcut: shortcutDisplay)
                }
            }
            .id(model.step)
            .transition(stepTransition)
            // Fixed area above the footer: a step never pushes the footer around.
            .frame(width: Self.size.width, height: Self.size.height - Self.footerHeight - Self.topInset, alignment: .top)
            .clipped()
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, Self.topInset)

            footer(trusted: model.isTrusted(p))
                .frame(height: Self.footerHeight)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.88), value: model.step)
        .background(WindowReader(window: $window))
        // The window previews the chosen theme (Look step) and keeps it afterwards.
        .onChange(of: window) { applyAppearance() }
        .onChange(of: controller.settings.appearance) { applyAppearance() }
        .onAppear { p.refresh(); p.startWatching() }
        .onDisappear { p.stopWatching() }
    }

    private var shortcutDisplay: String {
        (controller.settings.effectiveShortcut ?? Shortcut.default).displayString
    }

    private func applyAppearance() {
        window?.appearance = controller.settings.appearance.nsAppearance
    }

    private var stepTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let x: CGFloat = model.forward ? 44 : -44
        return .asymmetric(insertion: .offset(x: x).combined(with: .opacity),
                           removal: .offset(x: -x).combined(with: .opacity))
    }

    // MARK: Footer

    private func footer(trusted: Bool) -> some View {
        ZStack {
            if !model.isPermissionsOnly {
                StepDots(count: model.steps.count, current: model.index)
            }
            HStack {
                leadingButton(trusted: trusted)
                Spacer()
                primaryButton(trusted: trusted)
            }
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func leadingButton(trusted: Bool) -> some View {
        if model.step == .welcome {
            Button("Skip setup") {
                if trusted { onFinish(false) } else { model.skipToPermissions() }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.leading, 6)
        } else if !model.isFirst {
            Button("Go back") { model.back() }
                .buttonStyle(BrandButtonStyle(prominent: false))
                .focusEffectDisabled() // the rectangular focus ring doesn't fit a capsule
        }
    }

    @ViewBuilder
    private func primaryButton(trusted: Bool) -> some View {
        switch model.step {
        case .welcome:
            primary("Begin setup") { model.next() }
        case .permissions where model.isPermissionsOnly:
            primary(trusted ? "Done" : "Later", prominent: trusted) { onFinish(false) }
        case .permissions:
            // Accessibility is required for switching; it can still be granted later from the menu bar.
            primary(trusted ? "Continue" : "Skip for now", prominent: trusted) { model.next() }
        case .done:
            primary("Swoop Away", systemImage: "arrow.right") { onFinish(trusted) }
        default:
            primary("Continue") { model.next() }
        }
    }

    private func primary(_ title: String, systemImage: String? = nil, prominent: Bool = true,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                if let systemImage { Image(systemName: systemImage).font(.system(size: 12, weight: .semibold)) }
            }
        }
        .buttonStyle(BrandButtonStyle(prominent: prominent))
        .focusEffectDisabled()
        .keyboardShortcut(.defaultAction)
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    let shortcut: String

    var body: some View {
        VStack(spacing: 0) {
            BrandIcon(size: 76)
                .padding(.bottom, 12)
            StepHeader(title: "Welcome to Swoop",
                       subtitle: "Every window, one keystroke. Press \(shortcut), type a few letters, hit Return — you're there. Even on other desktops.")
            // The demo screenshots, stacked like panels: the full grid behind, a search in front.
            ZStack(alignment: .top) {
                Image("OnboardingGrid")
                    .resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .frame(width: 580)
                    .opacity(0.32)
                    .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
                Image("OnboardingSearch")
                    .resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .frame(width: 400)
                    .shadow(color: .black.opacity(0.30), radius: 20, y: 12)
                    .offset(y: 34)
            }
            .frame(height: 262, alignment: .top)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0.62), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .padding(.top, 24)
            .accessibilityHidden(true)
        }
    }
}

private struct PermissionsStep: View {
    let controller: AppController
    let granted: Bool

    var body: some View {
        let p = controller.permissions
        VStack(spacing: 0) {
            SymbolBadge(systemName: granted ? "checkmark.shield.fill" : "lock.shield.fill",
                        color: granted ? .green : Brand.orange)
                .padding(.bottom, 16)
            StepHeader(title: granted ? "Swoop can see your windows" : "Let Swoop see your windows",
                       subtitle: "Swoop needs Accessibility to list the windows of other apps and switch to the exact one you pick. Window information never leaves this Mac.")

            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: granted ? "checkmark.circle.fill" : "hand.raised.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(granted ? .green : Brand.orange)
                            .contentTransition(.symbolEffect(.replace))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Accessibility").font(.headline)
                            Text(granted ? "Granted — \(controller.registry.entries.count) windows found." : "Not granted yet")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !granted {
                            Button("Grant Access") { p.requestAccessibility() }
                                .buttonStyle(BrandButtonStyle())
                                .focusEffectDisabled()
                        }
                    }
                    if !granted {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("In System Settings → Privacy & Security → Accessibility, turn on **Swoop**. This screen updates by itself; no restart needed.")
                            Text("Already on but still not granted? Turn it off and on again.")
                                .foregroundStyle(.secondary)
                            Button("Open System Settings") { p.openAccessibilitySettings() }
                                .buttonStyle(.link)
                        }
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(width: 540)
            .padding(.top, 26)
            .animation(.easeOut(duration: 0.25), value: granted)

            Label("No Input Monitoring or Screen Recording: Swoop never reads your typing or your screen.",
                  systemImage: "eye.slash")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 18)
        }
    }
}

private struct ShortcutStep: View {
    let controller: AppController
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var message: String?

    var body: some View {
        @Bindable var settings = controller.settings
        VStack(spacing: 0) {
            SymbolBadge(systemName: "keyboard", color: Brand.orange)
                .padding(.bottom, 16)
            StepHeader(title: "Your shortcut",
                       subtitle: "Press it anywhere to open Swoop. Click to record a different one; you can change it later in Settings.")

            ShortcutRecorder(shortcut: $settings.shortcut, allowBareKeys: settings.allowBareTab, onRecordingChange: { recording in
                if recording { controller.hotkeys.unregister() } else { controller.applyShortcut() }
            }, onRejected: { message = $0 }, large: true)
                .padding(.top, 24)
            Group {
                if let warning = controller.shortcutError ?? settings.shortcut.knownConflict.map({ "May conflict with: \($0)." }) {
                    Label(warning, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                } else if let message {
                    Label(message, systemImage: "info.circle").foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 5) {
                        Text("Try it now:")
                        Keycap(settings.effectiveShortcut?.displayString ?? Shortcut.default.displayString)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .frame(height: 26)
            .padding(.top, 8)

            Text("When you release the shortcut")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.top, 22)
            HStack(spacing: 12) {
                ChoiceCard(title: "Keep the switcher open", detail: "Look around, search, then press Return.",
                           systemImage: "rectangle.grid.3x2", selected: settings.switcherMode == .stayOpen) {
                    settings.switcherMode = .stayOpen
                }
                ChoiceCard(title: "Switch on release", detail: "Like ⌘Tab: hold the modifier, tap to move, let go.",
                           systemImage: "hand.point.up.left", selected: settings.switcherMode == .switchOnRelease) {
                    settings.switcherMode = .switchOnRelease
                }
            }
            .padding(.top, 10)

            Toggle("Launch Swoop at login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .padding(.top, 20)
                .onChange(of: launchAtLogin) {
                    LaunchAtLogin.set(launchAtLogin)
                    launchAtLogin = LaunchAtLogin.isEnabled
                }
        }
        .onChange(of: settings.shortcut) { message = nil; controller.applyShortcut() }
    }
}

private struct LookStep: View {
    @Bindable var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(title: "Make it yours",
                       subtitle: "Pick how your windows are shown. You can change this any time in Settings.")

            // The demo screenshot of the chosen layout.
            Image(previewImage)
                .resizable().aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(maxWidth: 520, maxHeight: 190)
                .shadow(color: .black.opacity(0.22), radius: 14, y: 8)
                .id(settings.panelLayout)
                .transition(.opacity)
                .frame(height: 190)
                .padding(.top, 22)
                .accessibilityHidden(true)

            VisualPicker(options: PanelLayout.allCases, selection: $settings.panelLayout, label: \.label) {
                LayoutThumbnail(layout: $0)
            }
            .padding(.top, 18)

            HStack(spacing: 12) {
                Text("Theme").foregroundStyle(.secondary)
                Picker("Theme", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 320)
            }
            .padding(.top, 14)
        }
        .animation(.easeOut(duration: 0.2), value: settings.panelLayout)
    }

    private var previewImage: String {
        switch settings.panelLayout {
        case .grid: "OnboardingGrid"
        case .compactList: "OnboardingListCompact"
        case .comfortableList: "OnboardingListComfortable"
        }
    }
}

private struct SupportStep: View {
    let controller: AppController
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            SymbolBadge(systemName: model.supported ? "heart.fill" : "heart", color: .pink)
                .padding(.bottom, 16)
            StepHeader(title: model.supported ? "Thank you!" : "Free and open source",
                       subtitle: model.supported
                           ? "That really helps Swoop keep going. ♥"
                           : "No ads, no tracking, no account. If Swoop saves you time, here's how you can help it grow.")

            VStack(spacing: 10) {
                LinkRow(systemImage: "cup.and.saucer.fill", color: Brand.orange, title: "Buy me a coffee",
                        detail: "Supports the time that goes into fixes and new features.") {
                    open(AppLinks.buyMeACoffee)
                }
                LinkRow(systemImage: "star.fill", color: .yellow, title: "Star Swoop on GitHub",
                        detail: "Helps other people discover it.") {
                    open(AppLinks.repository)
                }
                LinkRow(systemImage: "exclamationmark.bubble.fill", color: .blue, title: "Report a problem or suggest a feature",
                        detail: "Any time, from the menu bar icon.") {
                    NSWorkspace.shared.open(AppLinks.newIssue(.featureRequest))
                }
            }
            .frame(width: 520)
            .padding(.top, 26)
        }
        .animation(.easeOut(duration: 0.25), value: model.supported)
    }

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
        model.supported = true
        controller.supportPrompt.markSupported()
    }
}

private struct DoneStep: View {
    let shortcut: String

    var body: some View {
        VStack(spacing: 0) {
            BrandIcon(size: 84)
                .padding(.bottom, 14)
            StepHeader(title: "You're all set",
                       subtitle: "Swoop lives in your menu bar. Press \(shortcut) anywhere to jump to any window.")

            Card {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                    tip(shortcut, "Open Swoop")
                    tip("abc", "Type to filter by app, title or project")
                    tip("← →", "Move the selection (or press the shortcut again)")
                    tip("↩", "Switch to the window")
                    tip("esc", "Close without switching")
                    tip("⌘ ,", "Settings")
                }
            }
            .frame(width: 440)
            .padding(.top, 26)
        }
    }

    private func tip(_ keys: String, _ text: String) -> some View {
        GridRow {
            Keycap(keys).gridColumnAlignment(.trailing)
            Text(text).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Building blocks

private struct StepHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 30, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.system(size: 14.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 540)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SymbolBadge: View {
    let systemName: String
    let color: Color
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 30, weight: .medium))
            .foregroundStyle(color)
            .frame(width: 64, height: 64)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(scheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.62),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

private struct ChoiceCard: View {
    let title: String
    let detail: String
    let systemImage: String
    let selected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: systemImage).font(.system(size: 17)).foregroundStyle(selected ? Brand.orange : .secondary)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Brand.orange : Color.secondary.opacity(0.5))
                }
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 250, height: 104, alignment: .topLeading)
            .background(scheme == .dark ? Color.white.opacity(selected ? 0.09 : 0.05) : Color.white.opacity(selected ? 0.85 : 0.55),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Brand.orange : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

/// A Raycast-style link row: icon, title + detail, and an outbound arrow.
private struct LinkRow: View {
    let systemImage: String
    let color: Color
    let title: String
    let detail: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 16))
                    .foregroundStyle(color)
                    .frame(width: 34, height: 34)
                    .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background((scheme == .dark ? Color.white : Color.white).opacity(scheme == .dark ? (hovering ? 0.10 : 0.06) : (hovering ? 0.85 : 0.6)),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityHint("Opens in your browser")
    }
}

private struct Keycap: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .frame(minWidth: 26)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
    }
}

private struct StepDots: View {
    let count: Int
    let current: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Brand.orange : Color.primary.opacity(0.18))
                    .frame(width: i == current ? 18 : 6, height: 6)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: current)
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

/// Gives the view its hosting NSWindow (to apply the theme preview).
private struct WindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { window = view.window }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        if nsView.window !== window { DispatchQueue.main.async { window = nsView.window } }
    }
}
