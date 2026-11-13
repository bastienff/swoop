import AppKit
import ApplicationServices
import OSLog
import SwoopCore

/// How a specific entry can be reached. Built by the registry from discovery results.
enum ActivationRoute: Sendable {
    /// A concrete window element (current Space, minimized, learned anchor, or main/focused).
    case element(AXElement)
    /// A non-selected native tab in the group whose visible window is `group`.
    case tab(group: AXElement, title: String)
    /// Known only from the app's Window menu.
    case menu
}

struct ActivationTarget: Sendable {
    let pid: pid_t
    let appName: String
    let title: String
    let route: ActivationRoute
    /// Windows of this app sharing `title` (menu duplicates).
    let titleMultiplicity: Int
    /// Tab groups observed or CG frames shared → Window-menu press is unsafe (F7).
    let mayHaveHiddenTabs: Bool
    let mainWindow: AXElement?
    let mainWindowTitle: String?
    /// Elements of *other* entries of this app with the same title. Never valid fallbacks.
    var siblingElements: [AXElement] = []

    var element: AXElement? { if case .element(let e) = route { e } else { nil } }
}

enum ActivationResult: Sendable, Equatable {
    case activated
    case failed(String)
}

/// Activates an exact window without moving it between Spaces (ARCHITECTURE §3).
/// Never uses `.moveToActiveSpace`, never sets window position, never presses a Window-menu item
/// for a possibly hidden tab on another Space.
@MainActor
final class WindowActivationService {
    private let log = Logger(subsystem: "com.bastienff.swoop", category: "activation")

    func activate(_ t: ActivationTarget) async -> ActivationResult {
        guard let app = NSRunningApplication(processIdentifier: t.pid), !app.isTerminated else {
            return .failed("\(t.appName) is no longer running.")
        }
        let axApp = AXElement.application(t.pid, timeout: 0.5)
        log.info("activate \(t.appName, privacy: .public) “\(t.title, privacy: .private)” route=\(String(describing: t.route), privacy: .public)")

        switch t.route {
        case .element(let w):
            guard w.isAlive else { return await navigateViaAppThenResolve(t, app: app, axApp: axApp) }
            focus(w, app: app, axApp: axApp)

        case .tab(let group, let title):
            if !currentWindows(axApp).contains(group) {
                guard group.isAlive else { return await navigateViaAppThenResolve(t, app: app, axApp: axApp) }
                // Step 1 (F9): navigate using the group's visible window.
                focus(group, app: app, axApp: axApp)
                let arrived = await waitUntil(timeout: 2.0) { [self] in currentWindows(axApp).contains(group) }
                guard arrived else { return .failed("Couldn't reach the desktop containing “\(title)”.") }
            }
            // Step 2: switch tab locally (safe; F5/F9).
            guard selectTabLocally(title: title, app: app, axApp: axApp) else {
                return .failed("The tab “\(title)” no longer exists.")
            }

        case .menu:
            if let main = t.mainWindow, t.mainWindowTitle == t.title, !t.siblingElements.contains(main), main.isAlive {
                focus(main, app: app, axApp: axApp)
            } else if !t.mayHaveHiddenTabs, t.titleMultiplicity == 1,
                      let item = WindowDiscoveryService.windowMenuItems(axApp).first(where: { $0.title == t.title }) {
                // Safe only when the target cannot be a hidden tab (F6 vs F7).
                yieldAndActivate(app, axApp: axApp)
                item.perform(kAXPressAction)
                yieldAndActivate(app, axApp: axApp)
            } else {
                return await navigateViaAppThenResolve(t, app: app, axApp: axApp)
            }
        }
        return await confirmFocus(t, app: app, axApp: axApp)
    }

    // MARK: - Steps

    /// Make `w` main + raised, then activate its app (F8). Unminimizes first if needed.
    private func focus(_ w: AXElement, app: NSRunningApplication, axApp: AXElement) {
        if w.bool(kAXMinimizedAttribute) == true { w.set(kAXMinimizedAttribute, kCFBooleanFalse) }
        w.set(kAXMainAttribute, kCFBooleanTrue)
        w.perform(kAXRaiseAction)
        yieldAndActivate(app, axApp: axApp)
        w.set(kAXFocusedAttribute, kCFBooleanTrue)
    }

    private func yieldAndActivate(_ app: NSRunningApplication, axApp: AXElement) {
        NSApp.yieldActivation(to: app)
        if !app.activate() {
            axApp.set(kAXFrontmostAttribute, kCFBooleanTrue)
        }
    }

    /// Fallback for menu-only/stale targets: go to the app's main window Space (no window moves),
    /// then find the target among windows/tabs on that Space. Fails safely otherwise.
    private func navigateViaAppThenResolve(_ t: ActivationTarget, app: NSRunningApplication, axApp: AXElement) async -> ActivationResult {
        if resolveLocally(t, app: app, axApp: axApp) { return await confirmFocus(t, app: app, axApp: axApp) }
        let unreachable = "Couldn't reach “\(t.title)” without moving it. Visit its desktop once so Swoop can learn where it is."
        let main = axApp.element(kAXMainWindowAttribute)
        if let main, currentWindows(axApp).contains(main) {
            // Navigating via the main window would not change Space: nothing more we can do safely.
            return .failed(unreachable)
        }
        if let main, main.isAlive {
            focus(main, app: app, axApp: axApp)
        } else {
            yieldAndActivate(app, axApp: axApp)
        }
        _ = await waitUntil(timeout: 1.5) { NSWorkspace.shared.frontmostApplication?.processIdentifier == t.pid }
        try? await Task.sleep(for: .milliseconds(250)) // let the Space transition settle
        if resolveLocally(t, app: app, axApp: axApp) { return await confirmFocus(t, app: app, axApp: axApp) }
        return .failed(unreachable)
    }

    /// Finds `t` on the current Space as a window or a tab and focuses it.
    @discardableResult
    private func resolveLocally(_ t: ActivationTarget, app: NSRunningApplication, axApp: AXElement) -> Bool {
        let siblings = Set(t.siblingElements)
        let windows = currentWindows(axApp).filter { !siblings.contains($0) }
        let matches = windows.filter { $0.title == t.title }
        // Ambiguous duplicates are only accepted when exactly one unclaimed candidate remains.
        if matches.count == 1 {
            focus(matches[0], app: app, axApp: axApp)
            return true
        }
        return selectTabLocally(title: t.title, app: app, axApp: axApp)
    }

    /// Presses the tab button titled `title` in a tab group on the current Space, then focuses it.
    private func selectTabLocally(title: String, app: NSRunningApplication, axApp: AXElement) -> Bool {
        for w in currentWindows(axApp) {
            guard let tabs = WindowDiscoveryService.tabButtons(of: w),
                  let tab = tabs.first(where: { $0.title == title }) else { continue }
            if (tab.int(kAXValueAttribute) ?? 0) != 1 { tab.perform(kAXPressAction) }
            let selected = currentWindows(axApp).first { $0.title == title } ?? w
            focus(selected, app: app, axApp: axApp)
            return true
        }
        return false
    }

    /// F10: after a Space switch macOS may give focus to another app on the destination Space,
    /// sometimes a few hundred ms after arrival. Confirm (by element identity when known, else title),
    /// re-assert, and keep guarding briefly after success.
    private func confirmFocus(_ t: ActivationTarget, app: NSRunningApplication, axApp: AXElement) async -> ActivationResult {
        func focusedIsTarget() -> Bool {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == t.pid else { return false }
            guard let focused = axApp.element(kAXFocusedWindowAttribute) else { return false }
            if let e = t.element, focused == e { return true }
            return focused.title == t.title
        }
        func reassert() {
            if let e = t.element, e.isAlive, currentWindows(axApp).contains(e) {
                focus(e, app: app, axApp: axApp)
            } else if let w = currentWindows(axApp).first(where: { $0.title == t.title }) {
                focus(w, app: app, axApp: axApp)
            } else {
                yieldAndActivate(app, axApp: axApp)
            }
        }
        var confirmed = false
        for attempt in 0..<3 {
            if await waitUntil(timeout: 0.6, focusedIsTarget) { confirmed = true; break }
            log.info("focus not confirmed (attempt \(attempt)); re-asserting")
            reassert()
        }
        // Guard window: a late activation of another app by the Space switch steals focus.
        let guardUntil = Date().addingTimeInterval(1.0)
        while Date() < guardUntil {
            try? await Task.sleep(for: .milliseconds(60))
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != t.pid {
                log.info("focus stolen after arrival; re-asserting once")
                reassert()
                confirmed = await waitUntil(timeout: 0.6) { NSWorkspace.shared.frontmostApplication?.processIdentifier == t.pid }
                break
            }
        }
        if confirmed || NSWorkspace.shared.frontmostApplication?.processIdentifier == t.pid { return .activated }
        return .failed("\(t.appName) didn't accept focus.")
    }

    // MARK: - Helpers

    private func currentWindows(_ axApp: AXElement) -> [AXElement] {
        axApp.elements(kAXWindowsAttribute).filter(WindowDiscoveryService.isSelectableWindow)
    }

    private func waitUntil(timeout: Double, _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(40))
        }
        return condition()
    }
}
