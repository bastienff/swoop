import AppKit
import ServiceManagement

/// Status-bar item and menu. Monochrome template image; no Dock icon.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    var onOpenSwoop: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenPermissions: (() -> Void)?
    /// Opens GitHub's pre-filled bug report / feature request form.
    var onReportProblem: (() -> Void)?
    var onSuggestFeature: (() -> Void)?
    var onSaveDiagnostics: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    /// A newer release found by an update check, shown at the top of the menu.
    var availableUpdate: () -> (version: String, page: URL)? = { nil }
    /// "About Swoop": the theme decides between the custom window and the standard panel.
    var onAbout: (() -> Void)?
    var shortcutDisplay: () -> String = { "" }
    var isAccessibilityTrusted: () -> Bool = { false }
    /// Screen frame of the menu-bar icon.
    var statusItemFrame: NSRect? { statusItem.button?.window?.frame }
    /// DEBUG builds: the Debug submenu, rebuilt each time the menu opens.
    var debugMenu: (() -> NSMenu)?

    override init() {
        super.init()
        if let button = statusItem.button {
            button.image = Self.statusImage()
        }
        menu.delegate = self
        statusItem.menu = menu
    }

    #if DEBUG
    func debugOpenMenu() { statusItem.button?.performClick(nil) }
    #endif

    /// The logo's orange, for update-available highlights in AppKit.
    static let brandOrange = NSColor(srgbRed: 0.95, green: 0.42, blue: 0.16, alpha: 1)

    /// Monochrome icon normally; the logo's orange while a newer version is known (quiet update hint).
    func setUpdateAvailable(_ available: Bool) {
        statusItem.button?.image = Self.statusImage(tint: available ? Self.brandOrange : nil)
        statusItem.button?.setAccessibilityLabel(available ? String(localized: "Swoop, update available") : "Swoop")
    }

    /// Template glyph matching the app icon: swap arrows (→ over ←, round tails tapering into swept heads)
    /// knocked out of a rounded square. Drawn as vector so it stays crisp at any backing scale; tinted by the
    /// system for light/dark, or a `tint` square with white arrows like the app icon (not a template then).
    /// Same arrow as `Tools/make_icon.swift`, slightly heavier for 18 pt (docs/design/brand/README.md).
    static func statusImage(tint: NSColor? = nil) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let square = CGPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerWidth: 4, cornerHeight: 4, transform: nil)
            var turn = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: rect.width, ty: rect.height)
            let arrow = swapArrow(y: 11.3, tail: 4.4, headStart: 11, tailWidth: 1.3, headWidth: 2, headLength: 3.1,
                                  headSpan: 5, sweep: 1.1)
            ctx.addPath(square)
            ctx.setFillColor(tint?.cgColor ?? NSColor.black.cgColor)
            ctx.fillPath()
            // Template: arrows knocked out of the square. Tinted: white arrows on the colored square.
            if tint == nil { ctx.setBlendMode(.clear) }
            ctx.setFillColor(NSColor.white.cgColor); ctx.setStrokeColor(NSColor.white.cgColor)
            for path in [arrow, arrow.copy(using: &turn)!] {
                ctx.addPath(path); ctx.fillPath()
                ctx.addPath(path); ctx.setLineWidth(0.35); ctx.setLineJoin(.round); ctx.strokePath() // rounded corners
            }
            return true
        }
        image.isTemplate = tint == nil
        image.accessibilityDescription = "Swoop"
        return image
    }

    /// A right-pointing swap arrow: round tail of `tailWidth` tapering to `headWidth`, then a head `headLength`
    /// long and `headSpan` tall with barbs swept back by `sweep`. Two subpaths with the same winding (shaft,
    /// head), so a nonzero fill is their union.
    private static func swapArrow(y: CGFloat, tail x0: CGFloat, headStart xe: CGFloat, tailWidth w0: CGFloat,
                                  headWidth w1: CGFloat, headLength head: CGFloat, headSpan: CGFloat, sweep: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: x0, y: y - w0 / 2))
        p.addLine(to: CGPoint(x: xe, y: y - w1 / 2))
        p.addLine(to: CGPoint(x: xe, y: y + w1 / 2))
        p.addLine(to: CGPoint(x: x0, y: y + w0 / 2))
        p.addArc(center: CGPoint(x: x0, y: y), radius: w0 / 2, startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: false)
        p.closeSubpath()
        let tip = CGPoint(x: xe + head, y: y), notch = CGPoint(x: xe - sweep * 0.2, y: y)
        let top = CGPoint(x: xe - sweep, y: y + headSpan / 2), bottom = CGPoint(x: xe - sweep, y: y - headSpan / 2)
        let cx = (2 * top.x + tip.x) / 3
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        func outward(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            let m = mid(a, b); return CGPoint(x: m.x + (m.x - cx) * 0.1, y: m.y + (m.y - y) * 0.1)
        }
        func inward(_ a: CGPoint, _ b: CGPoint) -> CGPoint { let m = mid(a, b); return CGPoint(x: m.x + sweep * 0.7, y: m.y) }
        p.move(to: notch)
        p.addQuadCurve(to: bottom, control: inward(notch, bottom))
        p.addQuadCurve(to: tip, control: outward(bottom, tip))
        p.addQuadCurve(to: top, control: outward(tip, top))
        p.addQuadCurve(to: notch, control: inward(top, notch))
        p.closeSubpath()
        return p
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let update = availableUpdate() {
            let title = String(localized: "Swoop \(update.version) Is Available", comment: "Menu bar menu; %@ is a version")
            let item = NSMenuItem(title: title, action: #selector(openUpdatePage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = update.page
            item.attributedTitle = NSAttributedString(string: title, attributes: [
                .foregroundColor: Self.brandOrange,
                .font: NSFont.menuFont(ofSize: 0).withWeight(.semibold),
            ])
            item.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(paletteColors: [.white, Self.brandOrange]))
            menu.addItem(item)
            menu.addItem(.separator())
        }
        let open = NSMenuItem(title: String(localized: "Open Swoop"), action: #selector(openSwoop), keyEquivalent: "")
        open.target = self
        let shortcut = shortcutDisplay()
        if !shortcut.isEmpty { open.title += "  (\(shortcut))" }
        menu.addItem(open)
        menu.addItem(.separator())

        let trusted = isAccessibilityTrusted()
        let ax = NSMenuItem(title: trusted ? String(localized: "Accessibility: Granted") : String(localized: "Accessibility: Not Granted — Fix"),
                            action: trusted ? nil : #selector(openPermissions), keyEquivalent: "")
        ax.target = self
        ax.image = NSImage(systemSymbolName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill", accessibilityDescription: nil)
        menu.addItem(ax)

        let login = NSMenuItem(title: String(localized: "Launch at Login"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())

        let settings = NSMenuItem(title: String(localized: "Settings"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let about = NSMenuItem(title: String(localized: "About Swoop"), action: #selector(about), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let updates = NSMenuItem(title: String(localized: "Check for Updates"), action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)
        let report = NSMenuItem(title: String(localized: "Report a Problem"), action: #selector(reportProblem), keyEquivalent: "")
        report.target = self
        report.image = NSImage(systemSymbolName: "exclamationmark.bubble", accessibilityDescription: nil)
        menu.addItem(report)
        // ⌥ reveals it in place of "Report a Problem" (standard alternate menu item).
        let diagnostics = NSMenuItem(title: String(localized: "Save Diagnostics Report"), action: #selector(saveDiagnostics), keyEquivalent: "")
        diagnostics.target = self
        diagnostics.image = NSImage(systemSymbolName: "doc.text.magnifyingglass", accessibilityDescription: nil)
        diagnostics.isAlternate = true
        diagnostics.keyEquivalentModifierMask = .option
        menu.addItem(diagnostics)
        let suggest = NSMenuItem(title: String(localized: "Suggest a Feature"), action: #selector(suggestFeature), keyEquivalent: "")
        suggest.target = self
        suggest.image = NSImage(systemSymbolName: "lightbulb", accessibilityDescription: nil)
        menu.addItem(suggest)
        let sponsor = NSMenuItem(title: String(localized: "Sponsor Swoop ♥"), action: #selector(openSponsor), keyEquivalent: "")
        sponsor.target = self
        sponsor.image = NSImage(systemSymbolName: "heart.fill", accessibilityDescription: nil)
        menu.addItem(sponsor)
        if let debugMenu {
            menu.addItem(.separator())
            let debug = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
            debug.image = NSImage(systemSymbolName: "ladybug", accessibilityDescription: nil)
            debug.submenu = debugMenu()
            menu.addItem(debug)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Quit Swoop"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func openSwoop() { onOpenSwoop?() }
    // After the menu has closed: activating from inside menu tracking (⌘, while the menu is open) is refused,
    // and Settings would open behind the frontmost app.
    @objc private func openSettings() { DispatchQueue.main.async { [weak self] in self?.onOpenSettings?() } }
    @objc private func openPermissions() { onOpenPermissions?() }
    @objc private func toggleLaunchAtLogin() { LaunchAtLogin.set(!LaunchAtLogin.isEnabled) }
    @objc private func reportProblem() { onReportProblem?() }
    @objc private func suggestFeature() { onSuggestFeature?() }
    @objc private func saveDiagnostics() { onSaveDiagnostics?() }
    @objc private func checkForUpdates() { onCheckForUpdates?() }
    @objc private func openUpdatePage(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.open(url) }
    }
    @objc private func openSponsor() { NSWorkspace.shared.open(AppLinks.sponsor) }
    @objc private func about() {
        if let onAbout { onAbout() } else { Self.showStandardAbout() }
    }

    /// The standard macOS About panel (Classic theme).
    static func showStandardAbout() {
        NSApp.activate()
        let credits = NSMutableAttributedString(string: String(localized: "Just a window switcher. Window information never leaves this Mac.") + "\n\n")
        credits.append(NSAttributedString(string: String(localized: "Swooped you to the right window? Sponsor Swoop ♥"),
                                          attributes: [.link: AppLinks.sponsor]))
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        credits.addAttributes([.paragraphStyle: centered, .font: NSFont.systemFont(ofSize: 11)],
                              range: NSRange(location: 0, length: credits.length))
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        // The panel is a plain NSPanel: it's the window that appeared (first time) or the one found before.
        if let new = NSApp.windows.first(where: { !before.contains(ObjectIdentifier($0)) && $0 is NSPanel && $0.isVisible }) {
            aboutPanel = new
        }
        if let aboutPanel { frost(aboutPanel) }
    }

    private static weak var aboutPanel: NSWindow?

    /// Gives the standard About panel the same frosted look as the switcher: a clear window background with a
    /// behind-window blur under its content. Public API only; skipped if the panel isn't found.
    private static func frost(_ panel: NSWindow) {
        guard let frame = panel.contentView?.superview else { return }
        BringToFront.show(panel) // like Swoop's own windows: never opens hidden behind the frontmost app
        guard !frame.subviews.contains(where: { $0.identifier?.rawValue == "swoop.frost" }) else { return }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        let blur = NSVisualEffectView(frame: frame.bounds)
        blur.identifier = NSUserInterfaceItemIdentifier("swoop.frost")
        blur.autoresizingMask = [.width, .height]
        blur.blendingMode = .behindWindow
        blur.state = .active
        let dark = panel.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        blur.material = dark ? .hudWindow : .popover
        frame.addSubview(blur, positioned: .below, relativeTo: nil)
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    @discardableResult
    static func set(_ enabled: Bool) -> Error? {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error
        }
    }
}

private extension NSFont {
    func withWeight(_ weight: NSFont.Weight) -> NSFont {
        let d = fontDescriptor.addingAttributes([.traits: [NSFontDescriptor.TraitKey.weight: weight]])
        return NSFont(descriptor: d, size: pointSize) ?? self
    }
}
