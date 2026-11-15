import AppKit
import os
import ApplicationServices
import SwoopCore

/// Static facts about a running app, captured on the main actor.
struct AppInfo: Sendable {
    let pid: pid_t
    let bundleID: String?
    let name: String
    let launchDate: Date?
}

/// A visible window element and the titles of all tabs in its native tab group (if any).
struct TabGroupInfo: Sendable {
    let window: AXElement
    let tabTitles: [String]      // includes the selected tab
}

/// Everything discovered for one app in one pass.
struct AppSnapshot: Sendable {
    let app: AppInfo
    var observations: [WindowObservation<AXElement>] = []
    /// Elements currently visible on the active Space (incl. minimized).
    var visible: [AXElement] = []
    /// Tab groups read in this pass (visible windows and readable anchors).
    var tabGroups: [TabGroupInfo] = []
    /// Anchors that turned out to be dead.
    var deadAnchors: [AXElement] = []
    var mainWindow: AXElement?
    var mainWindowTitle: String?
    /// Window-menu titles (all Spaces), for menu-only activation.
    var menuTitles: [String] = []
    /// True if a native tab group was seen, or CG frames suggest hidden tabs (shared identical frames).
    var mayHaveHiddenTabs = false
    /// False if the app didn't answer AX (unresponsive / no permission).
    var responsive = true
    /// Error reading the app's window list, if any (diagnostics).
    var windowsError: AXError?
    /// How long this app's discovery took (diagnostics: slow or hung apps).
    var duration: TimeInterval = 0
}

/// Window frames of every app on every Space from the window server (no permission needed for frames).
/// Hidden native tabs share their group's exact frame (F4), which is what the safety checks rely on.
struct WindowCensus: Sendable {
    struct FrameKey: Hashable, Sendable {
        let x, y, w, h: Int
        init(_ r: CGRect) { x = Int(r.minX.rounded()); y = Int(r.minY.rounded()); w = Int(r.width.rounded()); h = Int(r.height.rounded()) }
    }
    /// Normal-sized (>120 pt) layer-0 windows per pid, counted per frame.
    var frames: [pid_t: [FrameKey: Int]] = [:]
    /// All layer-0 windows per pid and frame, any size (for the hidden-tab safety check).
    var allFrames: [pid_t: [FrameKey: Int]] = [:]

    func windowCount(_ pid: pid_t) -> Int { frames[pid]?.values.reduce(0, +) ?? 0 }
    func sharesFrames(_ pid: pid_t) -> Bool { frames[pid]?.values.contains { $0 > 1 } ?? false }
    func count(_ pid: pid_t, _ frame: FrameKey) -> Int { allFrames[pid]?[frame] ?? 0 }

    /// The last census taken, for callers that accept a slightly old one.
    private static let cache = OSAllocatedUnfairLock<(at: Date, census: WindowCensus)?>(initialState: nil)

    /// A census at most `maxAge` seconds old (0 → always fresh). Listing every window on every Space is
    /// the most expensive part of a one-app refresh (~5 ms), so frequent title-only refreshes reuse one.
    static func current(maxAge: TimeInterval) -> WindowCensus {
        if maxAge > 0, let hit = cache.withLock({ $0 }), Date().timeIntervalSince(hit.at) <= maxAge { return hit.census }
        let census = current()
        cache.withLock { $0 = (Date(), census) }
        return census
    }

    static func current() -> WindowCensus {
        var c = WindowCensus()
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return c }
        for w in list where (w[kCGWindowLayer as String] as? Int) == 0 {
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t,
                  let b = w[kCGWindowBounds as String] as? [String: Double],
                  let width = b["Width"], let height = b["Height"] else { continue }
            let key = FrameKey(CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: width, height: height))
            c.allFrames[pid, default: [:]][key, default: 0] += 1
            if width > 120, height > 120 { c.frames[pid, default: [:]][key, default: 0] += 1 }
        }
        return c
    }
}

/// Window discovery (see ARCHITECTURE §2). Public Accessibility APIs, plus optional recovery of
/// already-vended elements on other Spaces through `RemoteElements` (§2a).
enum WindowDiscoveryService {
    static let windowMenuItemIdentifier = "makeKeyAndOrderFront:"
    static let acceptedSubroles: Set<String> = [kAXStandardWindowSubrole as String, kAXDialogSubrole as String]

    /// Discovers all `apps` concurrently, yielding each app's snapshot as soon as it is ready, so one
    /// slow or unresponsive app (e.g. still launching right after login) doesn't hold back the others.
    /// `censusMaxAge` > 0 only for title-change refreshes: titles don't move windows or form tab groups,
    /// so a recent census is still valid for the hidden-tab safety check (F7).
    static func discover(apps: [AppInfo], anchors: [pid_t: [AXElement]], recovery: RemoteWindowRecovery?,
                         censusMaxAge: TimeInterval = 0) -> AsyncStream<AppSnapshot> {
        AsyncStream { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let census = WindowCensus.current(maxAge: censusMaxAge)
                DispatchQueue.concurrentPerform(iterations: apps.count) { i in
                    let app = apps[i]
                    var snap = discover(app: app, anchors: anchors[app.pid] ?? [], recovery: recovery, census: census)
                    if census.sharesFrames(app.pid) { snap.mayHaveHiddenTabs = true }
                    cont.yield(snap)
                }
                cont.finish()
            }
        }
    }

    /// Single-app discovery. Synchronous AX IPC; call off the main thread.
    static func discover(app: AppInfo, anchors: [AXElement], recovery: RemoteWindowRecovery?, census: WindowCensus) -> AppSnapshot {
        let start = Date()
        var snap = discoverSources(app: app, anchors: anchors, recovery: recovery, census: census)
        snap.duration = Date().timeIntervalSince(start)
        return snap
    }

    private static func discoverSources(app: AppInfo, anchors: [AXElement], recovery: RemoteWindowRecovery?, census: WindowCensus) -> AppSnapshot {
        var snap = AppSnapshot(app: app)
        let axApp = AXElement.application(app.pid)

        // 1. Visible windows (current Space + minimized). F1.
        let (err, value) = axApp.raw(kAXWindowsAttribute)
        if err != .success { snap.windowsError = err }
        // Unresponsive app: keep going with the other sources (they may also time out quickly).
        if err == .cannotComplete { snap.responsive = false }
        let windows = (value as? [AnyObject])?.compactMap { v -> AXElement? in
            CFGetTypeID(v) == AXUIElementGetTypeID() ? AXElement(v as! AXUIElement) : nil
        } ?? []
        var known = Set<AXElement>()
        for w in windows where isSelectableWindow(w) {
            known.insert(w)
            snap.visible.append(w)
            addWindow(w, source: .visible, into: &snap)
        }

        // 2. Learned anchors from previously visited Spaces.
        for a in anchors where !known.contains(a) {
            guard a.isAlive, isSelectableWindow(a) else { snap.deadAnchors.append(a); continue }
            known.insert(a)
            addWindow(a, source: .anchor, into: &snap)
        }

        // 3. Main / focused window — works for off-Space windows (F2).
        let main = axApp.element(kAXMainWindowAttribute)
        snap.mainWindow = main
        snap.mainWindowTitle = main?.title
        for w in [main, axApp.element(kAXFocusedWindowAttribute)].compactMap({ $0 }) where !known.contains(w) {
            guard isSelectableWindow(w) else { continue }
            known.insert(w)
            addWindow(w, source: .mainOrFocused, into: &snap)
        }

        // 4. Window-menu list: every AppKit window on every Space, with titles (F3).
        let menuItems = windowMenuItems(axApp)
        for item in menuItems {
            let title = item.title ?? ""
            let minimized = item.string("AXMenuItemMarkChar") == "◆"
            snap.menuTitles.append(title)
            snap.observations.append(WindowObservation(title: title, source: .menuOnly, isMinimized: minimized))
        }

        // 5. Recover elements of windows on other Spaces that some AX client already saw (§2a).
        if let recovery, snap.responsive, let key = RemoteWindowRecovery.key(pid: app.pid, launch: app.launchDate) {
            recover(key: key, app: app, menuItems: menuItems, known: &known, snap: &snap, recovery: recovery, census: census)
        }

        // An anchor/main element whose title is now a *non-selected* tab of some group has become a
        // hidden tab (the user switched tabs). Using it to navigate could relocate the group (F7):
        // drop it and forget the anchor.
        let groupWindows = Set(snap.tabGroups.map(\.window))
        let hiddenTabTitles = Set(snap.observations.filter { $0.source == .tab }.map(\.title))
        snap.observations.removeAll { o in
            guard o.source == .anchor || o.source == .mainOrFocused, let r = o.ref,
                  !groupWindows.contains(r), hiddenTabTitles.contains(o.title) else { return false }
            snap.deadAnchors.append(r)
            return true
        }
        if !snap.tabGroups.isEmpty { snap.mayHaveHiddenTabs = true }
        return snap
    }

    // MARK: - Recovery (§2a)

    private static func recover(key: String, app: AppInfo, menuItems: [AXElement], known: inout Set<AXElement>,
                                snap: inout AppSnapshot, recovery: RemoteWindowRecovery, census: WindowCensus) {
        // Remember the ids of every window we hold, so a Swoop restart can rebuild them directly.
        var heldIDs: [UInt64: AXElement] = [:]
        for e in known { if let id = RemoteElements.elementID(of: e) { heldIDs[id] = e } }
        recovery.remember(key, heldIDs.keys)
        guard hasUnreachableWindows(snap, census: census) else { return }

        // Fast path: ids found by earlier sweeps or remembered from a previous Swoop run.
        var candidates: [AXElement] = []
        var dead: [UInt64] = []
        for id in recovery.knownIDs(key) where heldIDs[id] == nil {
            guard let e = RemoteElements.element(pid: app.pid, id: id) else { continue }
            let (err, role) = e.raw(kAXRoleAttribute)
            if err == .invalidUIElement { dead.append(id); continue }
            guard (role as? String) == (kAXWindowRole as String), isSelectableWindow(e), !known.contains(e) else { continue }
            candidates.append(e)
        }
        recovery.forget(key, dead)
        adopt(candidates, pid: app.pid, known: &known, snap: &snap, census: census)

        guard hasUnreachableWindows(snap, census: census) else { return }
        // Still missing windows: sweep ids not covered yet, in the background. The newest ids we can see
        // (menu items are re-vended on every read) bound where already-vended windows can be.
        let seen = heldIDs.keys.max() ?? 0
        let highWater = max(seen, menuItems.compactMap(RemoteElements.elementID).max() ?? 0,
                            candidates.compactMap(RemoteElements.elementID).max() ?? 0)
        recovery.requestSweep(key: key, pid: app.pid, highWater: highWater, knownWindows: Array(known))
    }

    /// True if the Window menu lists titles no element/tab explains, or (apps without a window list)
    /// the window server has more windows than we can reach.
    private static func hasUnreachableWindows(_ snap: AppSnapshot, census: WindowCensus) -> Bool {
        let merged = WindowMerger.merge(snap.observations)
        if merged.contains(where: { $0.source == .menuOnly && !$0.title.isEmpty }) { return true }
        return snap.menuTitles.isEmpty && census.windowCount(snap.app.pid) > merged.count
    }

    /// Adds recovered elements that are provably safe to focus (RemoteRecoveryPolicy). Group windows
    /// first: each one explains all of its tabs, which the standalone check needs.
    private static func adopt(_ candidates: [AXElement], pid: pid_t, known: inout Set<AXElement>,
                              snap: inout AppSnapshot, census: WindowCensus) {
        guard !candidates.isEmpty else { return }
        var plain: [AXElement] = []
        for e in candidates {
            guard let tabs = tabButtons(of: e), tabs.count > 1 else { plain.append(e); continue }
            let selected = tabs.first { ($0.int(kAXValueAttribute) ?? 0) == 1 }?.title
            let verdict = RemoteRecoveryPolicy.classify(title: e.title ?? "", selectedTabTitle: .some(selected),
                                                        knownHiddenTabTitles: [], windowsSharingFrame: 0, accountedSharingFrame: 0)
            if verdict == .anchor, selected != nil {
                known.insert(e)
                addWindow(e, source: .anchor, into: &snap)
            }
        }
        guard !plain.isEmpty else { return }

        let hiddenTitles = Set(snap.observations.filter { $0.source == .tab }.map(\.title))
        // How many windows with each frame known elements explain: a group window all its tabs, another
        // window itself, a known hidden tab nothing (its group already counts it).
        let groupSizes = Dictionary(snap.tabGroups.map { ($0.window, $0.tabTitles.count) }, uniquingKeysWith: max)
        var accounted: [WindowCensus.FrameKey: Int] = [:]
        for e in known {
            guard let f = e.frame.map(WindowCensus.FrameKey.init) else { continue }
            if let n = groupSizes[e] { accounted[f, default: 0] += n }
            else if !hiddenTitles.contains(e.title ?? "") { accounted[f, default: 0] += 1 }
        }
        for e in plain {
            guard let f = e.frame.map(WindowCensus.FrameKey.init) else { continue }
            let title = e.title ?? ""
            let verdict = RemoteRecoveryPolicy.classify(
                title: title, selectedTabTitle: nil, knownHiddenTabTitles: hiddenTitles,
                windowsSharingFrame: census.count(pid, f), accountedSharingFrame: accounted[f] ?? 0)
            guard verdict == .anchor else { continue }
            known.insert(e)
            accounted[f, default: 0] += 1
            addWindow(e, source: .anchor, into: &snap)
        }
    }

    private static func addWindow(_ w: AXElement, source: WindowSource, into snap: inout AppSnapshot) {
        let title = w.title ?? ""
        let minimized = w.bool(kAXMinimizedAttribute) ?? false
        let fullScreen = w.bool("AXFullScreen") ?? false
        snap.observations.append(WindowObservation(title: title, source: source, isMinimized: minimized,
                                                   isFullScreen: fullScreen, ref: w))
        // Native tab group (F5): non-selected tabs become `.tab` entries anchored to this window.
        if let tabs = tabButtons(of: w), tabs.count > 1 {
            var titles: [String] = []
            for t in tabs {
                let tabTitle = t.title ?? ""
                titles.append(tabTitle)
                let selected = (t.int(kAXValueAttribute) ?? 0) == 1
                if !selected && tabTitle != title {
                    snap.observations.append(WindowObservation(title: tabTitle, source: .tab, ref: w))
                }
            }
            snap.tabGroups.append(TabGroupInfo(window: w, tabTitles: titles))
        }
    }

    static func isSelectableWindow(_ w: AXElement) -> Bool {
        guard w.role == (kAXWindowRole as String) else { return false }
        if let sub = w.subrole { return acceptedSubroles.contains(sub) }
        return true
    }

    /// `AXTabButton`s of the window's native tab bar, or nil if the window has no tab group.
    static func tabButtons(of window: AXElement) -> [AXElement]? {
        for child in window.children where child.role == (kAXTabGroupRole as String) {
            let buttons = child.children.filter { $0.subrole == "AXTabButton" }
            if !buttons.isEmpty { return buttons }
        }
        return nil
    }

    /// Items of the app's Window menu that represent windows (identifier `makeKeyAndOrderFront:`).
    static func windowMenuItems(_ axApp: AXElement) -> [AXElement] {
        guard let bar = axApp.element(kAXMenuBarAttribute) else { return [] }
        // The Window menu is near the end; scan from the end and stop at the first hit.
        for top in bar.children.reversed() {
            for menu in top.children {
                let items = menu.children.filter { $0.string("AXIdentifier") == windowMenuItemIdentifier }
                if !items.isEmpty { return items }
            }
        }
        return []
    }

    /// Dock badge labels (e.g. unread counts) keyed by app bundle path, read from the Dock's AX items
    /// (`AXStatusLabel`). Public AX; no extra permission beyond Accessibility.
    static func dockBadges() -> [String: String] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return [:] }
        let ax = AXElement.application(dock.processIdentifier, timeout: 0.2)
        var result: [String: String] = [:]
        for list in ax.children where list.role == (kAXListRole as String) {
            for item in list.children {
                guard let label = item.string("AXStatusLabel"), !label.isEmpty,
                      let url = item.value(kAXURLAttribute) as? URL else { continue }
                result[url.standardizedFileURL.path] = label
            }
        }
        return result
    }
}
