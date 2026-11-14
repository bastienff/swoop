import AppKit
import SwiftUI
import SwoopCore

/// The occasional "buy me a coffee / star on GitHub" card (SupportPromptPolicy): a small non-activating
/// card under the menu-bar icon, shown right after a successful switch. It never takes focus from the
/// window the user just switched to, and any choice is one click.
@MainActor
final class SupportPromptController {
    private static let defaultsKey = "supportPrompt.v1"
    private static let autoHideAfter: Duration = .seconds(60)

    private(set) var state: SupportPromptState
    private var panel: NSPanel?
    private var autoHide: Task<Void, Never>?
    /// Screen frame of the menu-bar icon, to place the card under it.
    var anchorFrame: () -> NSRect? = { nil }
    /// Theme and appearance (Swoop theme: brand surface, follows Light/Dark; Classic: dark HUD as before).
    weak var settings: AppSettings?

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode(SupportPromptState.self, from: data) {
            state = saved
        } else {
            state = SupportPromptState(firstSeen: Date())
        }
        save()
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    /// The user bought a coffee or starred the repo elsewhere (onboarding): don't ask again.
    func markSupported() {
        state = SupportPromptPolicy.resolve(state, .supported, now: Date())
        save()
    }

    /// Called after every successful switch; shows the card if it's due.
    func recordSwitch() {
        state.switches += 1
        save()
        guard !isVisible, SupportPromptPolicy.isDue(state, now: Date()) else { return }
        // Let the destination window settle first (focus confirmation runs ~1 s after arrival).
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1400))
            self?.show()
        }
    }

    func show() {
        autoHide?.cancel()
        let swoop = settings?.theme == .swoop
        let card = SupportCardView(switches: state.switches, swoop: swoop) { [weak self] action in self?.handle(action) }
        let hosting = NSHostingView(rootView: card)
        let size = hosting.fittingSize

        let p = panel ?? makePanel()
        // Both themes: the frosted blur behind. Classic: dark HUD material. Swoop: the material for the chosen
        // appearance, with the card's brand surface drawn see-through over it (like the switcher).
        let background = NSVisualEffectView()
        background.blendingMode = .behindWindow
        background.state = .active
        background.appearance = swoop ? settings?.appearance.nsAppearance : NSAppearance(named: .darkAqua)
        let dark = (background.appearance ?? NSApp.effectiveAppearance).bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        background.material = dark ? .hudWindow : .popover
        background.wantsLayer = true
        background.layer?.cornerRadius = 18
        background.layer?.cornerCurve = .continuous
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 0.5
        background.layer?.borderColor = NSColor.white.withAlphaComponent(dark ? 0.14 : 0.6).cgColor
        hosting.frame = NSRect(origin: .zero, size: size)
        background.addSubview(hosting)
        p.contentView = background
        present(p, size: size)
    }

    private func present(_ p: NSPanel, size: NSSize) {
        p.setFrame(NSRect(origin: origin(for: size), size: size), display: true)
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.25; p.animator().alphaValue = 1 }
        panel = p
        // Ignored → treated as "Maybe later".
        autoHide = Task { [weak self] in
            try? await Task.sleep(for: Self.autoHideAfter)
            guard !Task.isCancelled else { return }
            self?.handle(.later)
        }
    }

    private func handle(_ action: SupportCardView.Action) {
        autoHide?.cancel()
        switch action {
        case .coffee:
            NSWorkspace.shared.open(AppLinks.buyMeACoffee)
            state = SupportPromptPolicy.resolve(state, .supported, now: Date())
        case .star:
            NSWorkspace.shared.open(AppLinks.repository)
            state = SupportPromptPolicy.resolve(state, .supported, now: Date())
        case .later:
            state = SupportPromptPolicy.resolve(state, .later, now: Date())
        case .never:
            state = SupportPromptPolicy.resolve(state, .never, now: Date())
        }
        save()
        hide()
    }

    private func hide() {
        guard let p = panel else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; p.animator().alphaValue = 0 }) {
            MainActor.assumeIsolated { p.orderOut(nil) }
        }
    }

    private func makePanel() -> NSPanel {
        let p = SupportPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        return p
    }

    /// Under the menu-bar icon (right-aligned to it), else the top-right of the main screen.
    private func origin(for size: NSSize) -> NSPoint {
        let margin: CGFloat = 10
        if let icon = anchorFrame(), let screen = NSScreen.screens.first(where: { $0.frame.intersects(icon) }) {
            let v = screen.visibleFrame
            let x = min(max(icon.maxX - size.width + 12, v.minX + margin), v.maxX - size.width - margin)
            return NSPoint(x: x, y: v.maxY - size.height - margin)
        }
        let v = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        return NSPoint(x: v.maxX - size.width - margin, y: v.maxY - size.height - margin)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data, forKey: Self.defaultsKey) }
    }

    // MARK: Debug

    #if DEBUG
    /// Due on the next switch (and enough switches), even if previously declined.
    func debugMakeDue() {
        state.optedOut = false
        state.nextDue = Date.distantPast
        state.switches = max(state.switches, SupportPromptPolicy.minimumSwitches)
        save()
    }

    /// As on a fresh install: first card after 100 switches or 2 days.
    func debugReset() {
        state = SupportPromptState(firstSeen: Date())
        save()
    }

    var debugSummary: String {
        if state.optedOut { return "Never again · \(state.switches) switches · shown \(state.timesShown)×" }
        let due = SupportPromptPolicy.dueDate(state)
        let when = due <= Date() ? "due now" : "due \(due.formatted(date: .abbreviated, time: .shortened))"
        let first = state.timesShown == 0 ? " (or at \(SupportPromptPolicy.firstPromptSwitches) switches)" : ""
        return "\(when)\(first) · \(state.switches) switches · shown \(state.timesShown)×"
    }
    #endif
}

/// Key-capable so its buttons respond on first click, without activating Swoop.
private final class SupportPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct SupportCardView: View {
    enum Action { case coffee, star, later, never }
    let switches: Int
    /// Swoop theme: brand surface, follows Light/Dark, orange coffee button. Classic: as before.
    var swoop = false
    let act: (Action) -> Void
    @Environment(\.colorScheme) private var scheme

    private var dark: Bool { scheme == .dark }
    private var titleColor: Color { swoop ? .primary : .white }
    private var bodyColor: Color { swoop ? .secondary : .white.opacity(0.7) }
    private var faintColor: Color { swoop ? Color.primary.opacity(0.5) : .white.opacity(0.5) }
    private var subtleFill: Color { swoop ? Color.primary.opacity(dark ? 0.12 : 0.07) : .white.opacity(0.14) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if swoop {
                    BrandIcon(size: 44, softInLight: true)
                } else {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().frame(width: 44, height: 44)
                }
                VStack(alignment: .leading, spacing: 4) {
                    (switches >= 2 ? Text("Swoop has switched you \(switches.formatted()) times") : Text("Enjoying Swoop?"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(titleColor)
                    Text("It's free, has no ads, and is made by one person. If it saves you time, a coffee or a GitHub star keeps it going.")
                        .font(.system(size: 12))
                        .foregroundStyle(bodyColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button { act(.later) } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(swoop ? Color.primary.opacity(0.5) : .white.opacity(0.55))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(swoop ? Color.primary.opacity(dark ? 0.1 : 0.06) : .white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .help("Maybe later")
            }
            HStack(spacing: 8) {
                Button { act(.coffee) } label: {
                    if swoop {
                        Label("Buy me a coffee", systemImage: "cup.and.saucer.fill")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(Capsule().fill(LinearGradient(colors: [Brand.orangeLight, Brand.orange], startPoint: .top, endPoint: .bottom)))
                            .shadow(color: Brand.orange.opacity(dark ? 0.35 : 0.16), radius: dark ? 7 : 4, y: 2)
                    } else {
                        Label("Buy me a coffee", systemImage: "cup.and.saucer.fill")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(Capsule().fill(Color(red: 1, green: 0.867, blue: 0)))
                    }
                }
                .buttonStyle(.plain)
                Button { act(.star) } label: {
                    Label("Star on GitHub", systemImage: "star.fill")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(titleColor)
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(Capsule().fill(subtleFill))
                }
                .buttonStyle(.plain)
            }
            HStack {
                Button("Maybe later") { act(.later) }
                Spacer()
                Button("Don't ask again") { act(.never) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(faintColor)
        }
        .padding(16)
        .frame(width: 360)
        .background { if swoop { BrandBackground(scale: 0.65).opacity(0.55) } } // frosted, like the switcher
    }
}
