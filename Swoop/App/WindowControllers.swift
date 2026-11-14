import AppKit
import OSLog
import SwiftUI

private let focusLog = Logger(subsystem: "com.bastienff.swoop", category: "focus")

/// Titled window that closes with Escape (fields that use Escape themselves, like the shortcut recorder,
/// consume it first).
final class EscapeClosableWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
}

/// Remembers the last app the user was in (other than Swoop), from workspace activation notifications.
/// Started at launch; costs one notification per app switch.
@MainActor
final class LastExternalApp {
    static let shared = LastExternalApp()
    private(set) var app: NSRunningApplication?
    private var token: NSObjectProtocol?

    func start() {
        guard token == nil else { return }
        record(NSWorkspace.shared.frontmostApplication)
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { LastExternalApp.shared.record(app) }
        }
    }

    private func record(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.activationPolicy == .regular else { return }
        self.app = app
        focusLog.debug("last external app: \(app.localizedName ?? "?", privacy: .public)")
    }
}

/// Swoop is a menu-bar app: showing Settings or onboarding makes it the active app. When its last window
/// closes, give focus back to the app the user was in, so typing works there without clicking.
@MainActor
final class FocusReturner {
    /// Kept for call sites; the target comes from `LastExternalApp`, which also covers windows opened while
    /// Swoop was already active (e.g. ⌘, from the switcher).
    func remember() {}

    /// Call when one of Swoop's windows closes.
    func windowClosed(_ closing: NSWindow?) {
        DispatchQueue.main.async {
            let other = Self.hasOtherWindow(than: closing)
            focusLog.debug("window closed: otherWindow=\(other) swoopActive=\(NSApp.isActive) target=\(LastExternalApp.shared.app?.localizedName ?? "nil", privacy: .public) front=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil", privacy: .public)")
            guard !other, NSApp.isActive else { return }
            Self.handBack()
            // macOS doesn't always honor the hand-off on the first try: check once more.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                focusLog.debug("after 350 ms: swoopActive=\(NSApp.isActive) front=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil", privacy: .public) keyWindow=\(NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "none", privacy: .public)")
                guard !Self.hasOtherWindow(than: closing), NSApp.isActive else { return }
                Self.handBack()
            }
        }
    }

    private static func hasOtherWindow(than closing: NSWindow?) -> Bool {
        NSApp.windows.contains { $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled) }
    }

    private static func handBack() {
        if let app = LastExternalApp.shared.app, !app.isTerminated {
            NSApp.yieldActivation(to: app)
            let ok = app.activate()
            focusLog.debug("hand back to \(app.localizedName ?? "?", privacy: .public): activate=\(ok)")
            if ok { return }
        }
        focusLog.debug("hand back: deactivate")
        NSApp.deactivate()
    }
}

/// Hosts SwiftUI content in a standard titled window; the accessory app activates to show it.
@MainActor
final class HostedWindowController<Content: View>: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let title: String
    private let makeContent: () -> Content
    /// Keep the window visible above other apps while it is open (permission onboarding), except
    /// above the windows the user needs to act in (`PermissionWindowLayering`).
    private let staysVisible: Bool
    /// Content runs under a transparent title bar (onboarding); the window moves by its background.
    private let chromeless: Bool
    private var activationObserver: NSObjectProtocol?
    private let focus = FocusReturner()
    var onClose: (() -> Void)?

    init(title: String, staysVisible: Bool = false, chromeless: Bool = false, content: @escaping () -> Content) {
        self.title = title
        self.staysVisible = staysVisible
        self.chromeless = chromeless
        self.makeContent = content
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: makeContent())
            hosting.sizingOptions = [.preferredContentSize]
            let w = EscapeClosableWindow(contentViewController: hosting)
            w.title = title
            w.styleMask = [.titled, .closable, .miniaturizable]
            if chromeless {
                w.styleMask.insert(.fullSizeContentView)
                w.titlebarAppearsTransparent = true
                w.titleVisibility = .hidden
                w.isMovableByWindowBackground = true
            }
            w.isReleasedWhenClosed = false
            w.delegate = self
            // Size to the content before centering (SwiftUI reports its size after the first layout).
            hosting.view.layoutSubtreeIfNeeded()
            let fitting = hosting.view.fittingSize
            if fitting.width > 0, fitting.height > 0 { w.setContentSize(fitting) }
            w.center()
            window = w
        }
        guard let window else { return }
        focus.remember()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // An accessory app launched in the background may not be allowed to activate (macOS 14+
        // cooperative activation): order the window front regardless, so it is never hidden.
        window.orderFrontRegardless()
        if staysVisible { startLayering() }
    }

    func close() { window?.close() }

    func windowWillClose(_ notification: Notification) {
        stopLayering()
        focus.windowClosed(notification.object as? NSWindow)
        onClose?()
        // Drop the hierarchy so observation/polling stops while closed.
        window = nil
    }

    // MARK: Layering

    private func startLayering() {
        if activationObserver == nil {
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated { self?.applyLayering(frontmost: app) }
            }
        }
        applyLayering(frontmost: NSWorkspace.shared.frontmostApplication)
    }

    private func stopLayering() {
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
    }

    private func applyLayering(frontmost app: NSRunningApplication?) {
        guard let window, window.isVisible else { return }
        switch PermissionWindowLayering.placement(frontmostBundleID: app?.bundleIdentifier,
                                                  isSelf: app?.processIdentifier == ProcessInfo.processInfo.processIdentifier) {
        case .float:
            window.level = .floating
            window.orderFrontRegardless()
        case .normal:
            window.level = .normal
        case .besideFrontWindow:
            // The user is acting in System Settings / the permission prompt / an auth sheet. macOS can't
            // stack us directly behind another app's window, so stay visible but move beside it.
            guard let pid = app?.processIdentifier else { return }
            placeBeside(pid: pid, window: window)
            // That app may still be opening its window: check again shortly.
            for delay in [0.4, 1.2] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, let w = self.window, w.isVisible,
                          NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                    self.placeBeside(pid: pid, window: w)
                }
            }
        }
    }

    private func placeBeside(pid: pid_t, window: NSWindow) {
        guard let blocker = PermissionWindowLayering.frontWindowFrame(of: pid) else { return }
        if !window.frame.intersects(blocker) {
            window.level = .floating
            window.orderFrontRegardless()
            return
        }
        let screen = NSScreen.screens.first { $0.frame.intersects(blocker) } ?? window.screen ?? NSScreen.main
        if let screen, let origin = PermissionWindowLayering.originBeside(blocker, size: window.frame.size, in: screen.visibleFrame) {
            window.setFrameOrigin(origin)
            window.level = .floating
            window.orderFrontRegardless()
        } else {
            window.level = .normal // no room anywhere: stay behind rather than cover it
        }
    }
}

/// Where the permission onboarding window sits relative to the frontmost app.
enum PermissionWindowLayering {
    enum Placement: Equatable { case float, normal, besideFrontWindow }

    /// Apps whose windows the user must be able to use while granting permission.
    static let permissionApps: Set<String> = [
        "com.apple.systempreferences",                       // System Settings
        "com.apple.accessibility.universalAccessAuthWarn",   // "… would like to control this computer"
        "com.apple.SecurityAgent",                           // password prompt
        "com.apple.LocalAuthentication.UIAgent",             // Touch ID prompt
        "com.apple.UserNotificationCenter",                  // legacy system alerts
        "com.apple.coreservices.uiagent",
    ]

    static func placement(frontmostBundleID: String?, isSelf: Bool) -> Placement {
        if isSelf { return .normal }  // our own Settings/About must not be covered either
        if let id = frontmostBundleID, permissionApps.contains(id) { return .besideFrontWindow }
        return .float
    }

    /// Frame (AppKit coordinates) of the app's frontmost visible window, from the window server
    /// (no permission needed).
    static func frontWindowFrame(of pid: pid_t) -> NSRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        for w in list where (w[kCGWindowOwnerPID as String] as? pid_t) == pid && (w[kCGWindowAlpha as String] as? Double ?? 1) > 0 {
            guard let b = w[kCGWindowBounds as String] as? [String: Double],
                  let x = b["X"], let y = b["Y"], let width = b["Width"], let height = b["Height"],
                  width > 80, height > 50 else { continue }
            return NSRect(x: x, y: primaryHeight - y - height, width: width, height: height) // flip to bottom-left origin
        }
        return nil
    }

    /// Origin for a window of `size` next to `blocker` without overlapping it, inside `visible`:
    /// left, right, below, above (in that order), or nil if nothing fits.
    static func originBeside(_ blocker: NSRect, size: NSSize, in visible: NSRect, gap: CGFloat = 16) -> NSPoint? {
        func clampY(_ y: CGFloat) -> CGFloat { min(max(y, visible.minY), visible.maxY - size.height) }
        func clampX(_ x: CGFloat) -> CGFloat { min(max(x, visible.minX), visible.maxX - size.width) }
        let topAligned = clampY(blocker.maxY - size.height)
        let candidates = [
            NSPoint(x: blocker.minX - gap - size.width, y: topAligned),
            NSPoint(x: blocker.maxX + gap, y: topAligned),
            NSPoint(x: clampX(blocker.midX - size.width / 2), y: blocker.minY - gap - size.height),
            NSPoint(x: clampX(blocker.midX - size.width / 2), y: blocker.maxY + gap),
        ]
        return candidates.first { p in
            let r = NSRect(origin: p, size: size)
            return visible.contains(r) && !r.intersects(blocker)
        }
    }
}

/// Settings window in the standard macOS preferences style: one toolbar tab per pane, the window
/// title follows the selected pane, and the window resizes to each pane's content.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let controller: AppController
    private var tabs: NSTabViewController?
    private let focus = FocusReturner()

    init(controller: AppController) {
        self.controller = controller
    }

    func show() {
        if window == nil {
            let tabs = NSTabViewController()
            tabs.tabStyle = .toolbar
            for pane in SettingsPane.allCases {
                let hosting = NSHostingController(rootView: pane.content(controller)
                    .frame(width: 560)
                    .fixedSize(horizontal: false, vertical: true)
                    .modifier(SettingsThemeStyle(settings: controller.settings)))
                hosting.sizingOptions = [.preferredContentSize]
                hosting.title = pane.title
                let item = NSTabViewItem(viewController: hosting)
                item.label = pane.title
                item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
                tabs.addTabViewItem(item)
            }
            let w = EscapeClosableWindow(contentViewController: tabs)
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.toolbarStyle = .preference
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
            self.tabs = tabs
            applyTheme()
        }
        focus.remember()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Swoop theme: the panes' brand background runs under a transparent toolbar. Classic: the standard
    /// window, untouched. Follows the setting live (it's changed from this very window).
    private func applyTheme() {
        guard let window else { return }
        let swoop = controller.settings.theme == .swoop
        if swoop { window.styleMask.insert(.fullSizeContentView) } else { window.styleMask.remove(.fullSizeContentView) }
        window.titlebarAppearsTransparent = swoop
        withObservationTracking {
            _ = controller.settings.theme
        } onChange: { [weak self] in
            Task { @MainActor in self?.applyTheme() }
        }
    }

    /// Selects a pane by index (used by the debug driver).
    func select(_ index: Int) {
        guard let tabs, tabs.tabViewItems.indices.contains(index) else { return }
        tabs.selectedTabViewItemIndex = index
    }

    func windowWillClose(_ notification: Notification) {
        focus.windowClosed(notification.object as? NSWindow)
        // Drop the hierarchy so observation/polling stops while closed.
        window = nil
        tabs = nil
    }
}
