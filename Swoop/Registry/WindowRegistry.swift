import AppKit
import Observation
import OSLog
import SwoopCore

/// Cached, merged list of selectable windows plus the information needed to activate each one.
@MainActor
@Observable
final class WindowRegistry {
    private(set) var entries: [WindowEntry] = []
    private(set) var lastRefresh: Date?
    private(set) var lastRefreshDuration: TimeInterval = 0
    /// True while a full refresh runs; the panel shows "Finding windows…" instead of "No windows"
    /// when nothing has been found yet (e.g. the first scan right after login).
    private(set) var isRefreshing = false

    @ObservationIgnored private var targets: [String: ActivationTarget] = [:]
    @ObservationIgnored private var snapshots: [pid_t: AppSnapshot] = [:]
    /// Window elements seen visible on some Space (learned anchors, ARCHITECTURE §2).
    @ObservationIgnored private var anchors: [pid_t: [AXElement]] = [:]
    @ObservationIgnored private var icons: [pid_t: NSImage] = [:]
    /// Dock badge per pid (e.g. Slack unread count), shown on the icon like the Dock does.
    private(set) var badges: [pid_t: String] = [:]
    /// Element recovery for windows on other Spaces (§2a); nil when the private symbols are unavailable.
    @ObservationIgnored private var recovery: RemoteWindowRecovery?
    /// App front-to-back order, computed once per refresh (not per app snapshot).
    @ObservationIgnored private var zOrder: [pid_t: Int] = [:]
    /// Regular apps as of the last full refresh (in `runningApplications` order). Listing every app and
    /// reading its activation policy costs a LaunchServices round-trip per app, so one-app refreshes reuse
    /// this; launches and quits trigger a full refresh that rebuilds it.
    @ObservationIgnored private var knownApps: [KnownApp] = []
    /// One-app refreshes per app name this session (diagnostics: shows which apps cause background work).
    @ObservationIgnored private var appRefreshCounts: [String: Int] = [:]
    private struct KnownApp {
        let info: AppInfo
        let bundlePath: String?

        init(_ app: NSRunningApplication) {
            info = AppInfo(pid: app.processIdentifier, bundleID: app.bundleIdentifier, name: app.localizedName ?? "App", launchDate: app.launchDate)
            bundlePath = app.bundleURL?.standardizedFileURL.path
        }
    }
    @ObservationIgnored private var refreshInFlight: Task<Void, Never>?
    @ObservationIgnored private var refreshQueued = false

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let recents: RecentWindowsStore
    @ObservationIgnored private let log = Logger(subsystem: "com.bastienff.swoop", category: "registry")

    init(settings: AppSettings, recents: RecentWindowsStore) {
        self.settings = settings
        self.recents = recents
        if RemoteElements.isAvailable {
            recovery = RemoteWindowRecovery { [weak self] pid in
                // A background sweep found windows: re-discover just that app.
                Task { @MainActor in await self?.refresh(pid: pid) }
            }
        }
    }

    /// A window was just created (AX notification). Windows always open on the current Space, so this
    /// is the cheapest moment to learn them; validation happens in the next discovery pass.
    func learnCreatedWindow(_ window: AXElement, pid: pid_t) {
        guard !(anchors[pid]?.contains(window) ?? false) else { return }
        anchors[pid, default: []].append(window)
        if let recovery, let id = RemoteElements.elementID(of: window),
           let key = RemoteWindowRecovery.key(pid: pid, launch: NSRunningApplication(processIdentifier: pid)?.launchDate) {
            recovery.remember(key, [id])
        }
    }

    func target(for id: String) -> ActivationTarget? { targets[id] }

    func icon(for pid: pid_t) -> NSImage {
        if let i = icons[pid] { return i }
        let image = NSRunningApplication(processIdentifier: pid)?.icon ?? NSWorkspace.shared.icon(for: .application)
        icons[pid] = image
        return image
    }

    // MARK: - Refresh

    /// Refreshes all apps. Concurrent calls coalesce into at most one extra pass.
    func refresh() async {
        if let inFlight = refreshInFlight {
            refreshQueued = true
            await inFlight.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            repeat {
                refreshQueued = false
                await performRefresh(only: nil)
            } while refreshQueued
        }
        refreshInFlight = task
        isRefreshing = true
        await task.value
        refreshInFlight = nil
        isRefreshing = false
    }

    /// Refreshes a single app (event-driven updates).
    /// `titleOnly`: triggered by title changes alone, so a census up to `titleCensusMaxAge` old is reused.
    func refresh(pid: pid_t, titleOnly: Bool = false) async {
        await performRefresh(only: pid, censusMaxAge: titleOnly ? Self.titleCensusMaxAge : 0)
    }

    static let titleCensusMaxAge: TimeInterval = 5

    private func performRefresh(only pid: pid_t?, censusMaxAge: TimeInterval = 0) async {
        #if DEBUG
        if demoMode { return }
        #endif
        guard AXIsProcessTrusted() else {
            entries = []; targets = [:]; snapshots = [:]; anchors = [:]
            return
        }
        let start = Date()
        let apps: [AppInfo]
        if let pid, !knownApps.isEmpty {
            // One app: look up only that one; everything else comes from the last full refresh.
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated, app.activationPolicy == .regular,
                  pid != ProcessInfo.processInfo.processIdentifier, !settings.hiddenApps.contains(app.bundleIdentifier) else { return }
            let known = KnownApp(app)
            if let i = knownApps.firstIndex(where: { $0.info.pid == pid }) { knownApps[i] = known } else { knownApps.append(known) }
            apps = [known.info]
            appRefreshCounts[known.info.name, default: 0] += 1
        } else {
            knownApps = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }
                // Hidden apps (Settings → Behavior) aren't enumerated at all.
                .filter { !settings.hiddenApps.contains($0.bundleIdentifier) }
                .map(KnownApp.init)
            apps = knownApps.map(\.info).filter { pid == nil || $0.pid == pid }
        }
        let running = knownApps
        let badgeTask = Task.detached { WindowDiscoveryService.dockBadges() }
        let alive = Set(running.map(\.info.pid))
        let appOrder = running.map(\.info.pid)
        zOrder = Self.appZOrder()
        let recovery = settings.recoverOtherSpaceWindows ? recovery : nil
        // Apply each app as soon as it reports, so the grid fills in progressively instead of
        // waiting for the slowest app. Snapshots from the previous pass stay until replaced.
        for await snap in WindowDiscoveryService.discover(apps: apps, anchors: anchors, recovery: recovery, censusMaxAge: censusMaxAge) {
            snapshots[snap.app.pid] = snap
            learnAnchors(from: snap)
            rebuildEntries(appOrder: appOrder)
        }
        let dockBadges = await badgeTask.value
        var newBadges: [pid_t: String] = [:]
        for app in running {
            if let path = app.bundlePath, let b = dockBadges[path] { newBadges[app.info.pid] = b }
        }
        if newBadges != badges { badges = newBadges }

        snapshots = snapshots.filter { alive.contains($0.key) }
        anchors = anchors.filter { alive.contains($0.key) }
        icons = icons.filter { alive.contains($0.key) }
        if pid == nil {
            self.recovery?.prune(keeping: Set(running.compactMap { RemoteWindowRecovery.key(pid: $0.info.pid, launch: $0.info.launchDate) }))
        }
        rebuildEntries(appOrder: appOrder)
        lastRefresh = Date()
        if pid == nil { lastRefreshDuration = Date().timeIntervalSince(start) }
        if settings.debugLogging && pid == nil { log.info("\(self.dump(), privacy: .public)") }
        log.debug("refresh \(pid.map(String.init) ?? "all", privacy: .public): \(self.entries.count) entries in \(Int(Date().timeIntervalSince(start) * 1000)) ms")
    }

    private func learnAnchors(from snap: AppSnapshot) {
        var set = anchors[snap.app.pid] ?? []
        let dead = Set(snap.deadAnchors)
        set.removeAll { dead.contains($0) }
        for o in snap.observations where o.source == .visible || o.source == .anchor || o.source == .mainOrFocused {
            if let r = o.ref, !o.isMinimized, !set.contains(r) { set.append(r) }
        }
        anchors[snap.app.pid] = set
    }

    // MARK: - Entries

    private func rebuildEntries(appOrder: [pid_t]) {
        var newEntries: [WindowEntry] = []
        var newTargets: [String: ActivationTarget] = [:]
        let orderedPids = snapshots.keys.sorted { a, b in
            let za = zOrder[a] ?? Int.max, zb = zOrder[b] ?? Int.max
            if za != zb { return za < zb }
            return (appOrder.firstIndex(of: a) ?? 0) < (appOrder.firstIndex(of: b) ?? 0)
        }
        for pid in orderedPids {
            guard let snap = snapshots[pid] else { continue }
            var observations = snap.observations
            if !settings.nativeTabDiscovery { observations.removeAll { $0.source == .tab } }
            let visibleSet = Set(snap.visible)
            let isVSCode = settings.vscodeEnhancements && VSCodeTitleParser.isVSCode(snap.app.bundleID)
            let merged = WindowMerger.merge(observations)
            var elementsByTitle: [String: [AXElement]] = [:]
            for m in merged where m.source != .tab && m.source != .menuOnly {
                if let r = m.ref { elementsByTitle[m.title, default: []].append(r) }
            }
            for m in merged {
                if m.source == .menuOnly && m.title.isEmpty { continue }
                if m.isMinimized && !settings.showMinimized { continue }
                if m.isFullScreen && !settings.includeFullScreen { continue }
                let id = "\(pid)|\(m.title)|\(m.ordinal)"
                let route: ActivationRoute
                let onCurrentSpace: Bool
                switch m.source {
                case .visible, .anchor, .mainOrFocused:
                    route = .element(m.ref!)
                    onCurrentSpace = m.source == .visible && !m.isMinimized
                case .tab:
                    route = .tab(group: m.ref!, title: m.title)
                    onCurrentSpace = visibleSet.contains(m.ref!)
                case .menuOnly:
                    route = .menu
                    onCurrentSpace = false
                }
                var entry = WindowEntry(
                    id: id, pid: pid, bundleID: snap.app.bundleID, appName: snap.app.name, title: m.title,
                    source: m.source, isMinimized: m.isMinimized, isFullScreen: m.isFullScreen,
                    isOnCurrentSpace: onCurrentSpace, isNativeTab: m.source == .tab)
                if isVSCode, let parsed = VSCodeTitleParser.parse(m.title) {
                    entry.projectName = parsed.project
                    entry.detail = parsed.detail
                }
                entry.lastUsed = recents.date(for: entry.recencyKey)
                newEntries.append(entry)
                let own: AXElement? = if case .element(let e) = route { e } else { nil }
                newTargets[id] = ActivationTarget(
                    pid: pid, appName: snap.app.name, title: m.title, route: route,
                    titleMultiplicity: m.titleMultiplicity, mayHaveHiddenTabs: snap.mayHaveHiddenTabs,
                    mainWindow: snap.mainWindow, mainWindowTitle: snap.mainWindowTitle,
                    siblingElements: (elementsByTitle[m.title] ?? []).filter { $0 != own })
            }
        }
        // Only publish real changes so progressive updates don't churn the open panel.
        if newEntries != entries { entries = newEntries }
        targets = newTargets
    }

    #if DEBUG
    /// Fixed, generic windows for README screenshots (`swctl demo`). Real discovery is paused.
    @ObservationIgnored private var demoMode = false

    struct DemoWindow {
        let appPath: String, appName: String, title: String
        var badge: String? = nil
        var tab = false, otherDesktop = false, minimized = false
        var selected = false
    }

    var isDemo: Bool { demoMode }
    var recoveryStats: (apps: Int, ids: Int)? { recovery?.stats }
    var anchorCount: Int { anchors.values.reduce(0) { $0 + $1.count } }

    /// Leaves demo mode and rediscovers real windows.
    func exitDemo() async {
        demoMode = false
        icons = [:]; badges = [:]; entries = []; targets = [:]; snapshots = [:]
        await refresh()
    }

    /// Drops in-memory anchors, as if Swoop had just relaunched (remembered ids are kept).
    func forgetAnchors() { anchors = [:] }

    /// Forgets remembered window ids and sweep cursors (and in-memory anchors).
    func resetRecovery() { anchors = [:]; recovery?.reset() }

    func loadDemo(_ windows: [DemoWindow]) {
        demoMode = true
        var list: [WindowEntry] = []
        var newBadges: [pid_t: String] = [:]
        var pidByApp: [String: pid_t] = [:]
        let now = Date()
        for (i, w) in windows.enumerated() {
            let pid = pidByApp[w.appPath] ?? pid_t(900_000 + pidByApp.count)
            pidByApp[w.appPath] = pid
            if icons[pid] == nil { icons[pid] = NSWorkspace.shared.icon(forFile: w.appPath) }
            if let b = w.badge { newBadges[pid] = b }
            let bundleID = Bundle(path: w.appPath)?.bundleIdentifier
            var e = WindowEntry(id: "demo|\(i)", pid: pid, bundleID: bundleID, appName: w.appName, title: w.title,
                                source: w.tab ? .tab : .visible, isMinimized: w.minimized,
                                isOnCurrentSpace: !w.otherDesktop && !w.minimized, isNativeTab: w.tab,
                                lastUsed: now.addingTimeInterval(-Double(i) * 60))
            if VSCodeTitleParser.isVSCode(bundleID), let parsed = VSCodeTitleParser.parse(w.title) {
                e.projectName = parsed.project
                e.detail = parsed.detail
            }
            list.append(e)
        }
        badges = newBadges
        entries = list
    }
    #endif

    func recordUse(of entry: WindowEntry) {
        recents.record(entry.recencyKey)
        if let i = entries.firstIndex(where: { $0.id == entry.id }) { entries[i].lastUsed = Date() }
    }

    /// Called when an app's focused window changes (outside or inside Swoop).
    func noteFocus(pid: pid_t, title: String) {
        let app = NSRunningApplication(processIdentifier: pid)
        let key = RecentUsage.key(bundleID: app?.bundleIdentifier ?? app?.localizedName ?? "", title: title)
        let now = Date()
        recents.record(key, at: now)
        if let i = entries.firstIndex(where: { $0.pid == pid && $0.title == title }) { entries[i].lastUsed = now }
    }

    /// Front-to-back order of apps by their frontmost on-screen window (no permission needed).
    private static func appZOrder() -> [pid_t: Int] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [:] }
        var order: [pid_t: Int] = [:]
        for w in list where (w[kCGWindowLayer as String] as? Int) == 0 {
            if let pid = w[kCGWindowOwnerPID as String] as? pid_t, order[pid] == nil { order[pid] = order.count }
        }
        return order
    }

    /// Debug description for Settings → Advanced and diagnostics.
    /// `includeTitles: false` replaces titles with their length (diagnostics reports without opt-in).
    /// One line per app from the last discovery pass, front to back (diagnostics report). No titles.
    /// `census` is the window server's view (every Space), `observed` the apps with live AX observers.
    func appDiagnostics(census: WindowCensus, observed: Set<pid_t>) -> [String] {
        let pids = snapshots.keys.sorted { (zOrder[$0] ?? Int.max, $0) < (zOrder[$1] ?? Int.max, $1) }
        return pids.compactMap { pid -> String? in
            guard let snap = snapshots[pid] else { return nil }
            let app = NSRunningApplication(processIdentifier: pid)
            let listed = entries.filter { $0.pid == pid }
            let bySource = Dictionary(grouping: listed, by: { "\($0.source)" }).map { "\($0.key) \($0.value.count)" }.sorted()
            let tabs = snap.tabGroups.reduce(0) { $0 + $1.tabTitles.count }
            var s = "\(snap.app.name) [\(snap.app.bundleID ?? "no bundle id")\(DiagnosticsInfo.appVersion(app).map { " \($0)" } ?? "")"
            s += DiagnosticsInfo.isElectron(app) ? ", Electron" : ""
            s += "] pid \(pid)"
            if let launched = snap.app.launchDate { s += ", running \(DiagnosticsInfo.duration(Date().timeIntervalSince(launched)))" }
            s += "\n    AX: \(snap.responsive ? "responds" : "NOT RESPONDING")"
            if let e = snap.windowsError { s += " (window list error \(DiagnosticsInfo.axErrorName(e)))" }
            s += ", \(Int(snap.duration * 1000)) ms, observer \(observed.contains(pid) ? "on" : "OFF")"
            s += ", refreshes \(appRefreshCounts[snap.app.name] ?? 0)"
            s += "\n    windows: \(snap.visible.count) on this desktop, \(census.windowCount(pid)) in window server (all desktops)"
            s += ", Window menu \(snap.menuTitles.isEmpty ? "none" : "\(snap.menuTitles.count) items")"
            s += ", tab groups \(snap.tabGroups.count)\(snap.tabGroups.isEmpty ? "" : " (\(tabs) tabs)")"
            s += ", anchors \(anchors[pid]?.count ?? 0)\(snap.mayHaveHiddenTabs ? ", may have hidden tabs" : "")"
            s += "\n    listed: \(listed.count)\(bySource.isEmpty ? "" : " (\(bySource.joined(separator: ", ")))")"
            return s
        }
    }

    /// Pids of the apps the last discovery pass covered.
    var discoveredPIDs: Set<pid_t> { Set(snapshots.keys) }

    func dump(includeTitles: Bool = true) -> String {
        var s = "Registry @ \(lastRefresh.map { "\($0)" } ?? "never") — \(entries.count) entries, full refresh \(Int(lastRefreshDuration * 1000)) ms\n"
        if !appRefreshCounts.isEmpty {
            s += "App refreshes this session: " + appRefreshCounts.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", ") + "\n"
        }
        for e in entries {
            let t = targets[e.id]
            let route = t?.route.kind ?? "?"
            let title = includeTitles ? e.title : "‹title, \(e.title.count) chars›"
            s += "\(e.appName) | \(title) | src=\(e.source) route=\(route) cur=\(e.isOnCurrentSpace) min=\(e.isMinimized) tabsRisk=\(t?.mayHaveHiddenTabs ?? false) mult=\(t?.titleMultiplicity ?? 0)\n"
        }
        for (pid, badge) in badges.sorted(by: { $0.key < $1.key }) {
            let name = snapshots[pid]?.app.name ?? "\(pid)"
            s += "badge \(name): \(badge.debugDescription) \(badge.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " "))\n"
        }
        return s
    }
}
