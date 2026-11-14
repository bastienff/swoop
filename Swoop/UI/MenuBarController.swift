import AppKit
import ServiceManagement

/// Status-bar item and menu (PRD §10). Monochrome template image; no Dock icon.
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

    /// Template glyph matching the app icon: swap arrows (→ over ←) knocked out of a rounded square.
    /// Drawn as vector so it stays crisp at any backing scale; tinted by the system for light/dark,
    /// or a `tint` square with white arrows like the app icon (not a template then).
    static func statusImage(tint: NSColor? = nil) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            func arrow(from p: CGPoint, to q: CGPoint, width w: CGFloat, head h: CGFloat) -> NSBezierPath {
                let bx = q.x - (q.x >= p.x ? 1 : -1) * h
                let path = NSBezierPath()
                path.move(to: CGPoint(x: p.x, y: p.y + w / 2))
                path.line(to: CGPoint(x: bx, y: q.y + w / 2))
                path.line(to: CGPoint(x: bx, y: q.y + h * 0.8))
                path.line(to: q)
                path.line(to: CGPoint(x: bx, y: q.y - h * 0.8))
                path.line(to: CGPoint(x: bx, y: q.y - w / 2))
                path.line(to: CGPoint(x: p.x, y: p.y - w / 2))
                path.close()
                return path
            }
            let square = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4)
            let arrows = arrow(from: CGPoint(x: 4.5, y: 11), to: CGPoint(x: 13.5, y: 11), width: 1.8, head: 3.4)
            arrows.append(arrow(from: CGPoint(x: 13.5, y: 7), to: CGPoint(x: 4.5, y: 7), width: 1.8, head: 3.4))
            if let tint {
                // Like the app icon: colored square, white arrows.
                tint.setFill()
                square.fill()
                NSColor.white.setFill()
                arrows.fill()
            } else {
                // Template: arrows knocked out of the square, tinted by the system.
                square.append(arrows)
                square.windingRule = .evenOdd
                NSColor.black.setFill()
                square.fill()
            }
            return true
        }
        image.isTemplate = tint == nil
        image.accessibilityDescription = "Swoop"
        return image
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
        let coffee = NSMenuItem(title: String(localized: "Buy Me a Coffee ♥"), action: #selector(buyMeACoffee), keyEquivalent: "")
        coffee.target = self
        coffee.image = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil)
        menu.addItem(coffee)
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
    @objc private func buyMeACoffee() { NSWorkspace.shared.open(AppLinks.buyMeACoffee) }
    @objc private func about() {
        if let onAbout { onAbout() } else { Self.showStandardAbout() }
    }

    /// The standard macOS About panel (Classic theme).
    static func showStandardAbout() {
        NSApp.activate()
        let credits = NSMutableAttributedString(string: String(localized: "Just a window switcher. Window information never leaves this Mac.") + "\n\n")
        credits.append(NSAttributedString(string: String(localized: "Swooped you to the right window? Buy me a coffee ☕"),
                                          attributes: [.link: AppLinks.buyMeACoffee]))
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        credits.addAttributes([.paragraphStyle: centered, .font: NSFont.systemFont(ofSize: 11)],
                              range: NSRange(location: 0, length: credits.length))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
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
