import AppKit
import ApplicationServices
import OSLog
import SwoopCore

/// Composition root: owns services and wires events (ARCHITECTURE §8).
@MainActor
final class AppController {
    let launchedAt = Date()
    let settings = AppSettings()
    let recents = RecentWindowsStore()
    let permissions = PermissionManager()
    let hotkeys = GlobalShortcutManager()
    let activation = WindowActivationService()
    let hud = HUDController()
    let supportPrompt = SupportPromptController()
    lazy var registry = WindowRegistry(settings: settings, recents: recents)
    lazy var searchModel = SearchViewModel(registry: registry, settings: settings)
    lazy var panel = SwoopPanelController(model: searchModel, settings: settings)
    lazy var menuBar = MenuBarController()
    lazy var observers = WorkspaceObserver(registry: registry, recents: recents)
    var openSettingsHandler: (() -> Void)?
    var selectSettingsPane: ((Int) -> Void)?
    var openOnboardingHandler: (() -> Void)?
    var closeOnboarding: (() -> Void)?
    var onAccessibilityGranted: (() -> Void)?

    private let log = Logger(subsystem: "com.bastienff.swoop", category: "app")
    private(set) var shortcutError: String?
    /// The activation in flight; cancelled when the switcher opens again so its focus guard
    /// doesn't pull the previous target back over the new panel.
    private var activationTask: Task<Void, Never>?
    /// The app most recently asked to come forward. macOS applies activations asynchronously, so for a
    /// moment after a switch it may not be frontmost yet (and can take focus from a just-reopened panel).
    private var lastActivation: (pid: pid_t, at: Date)?
    static let activationSettleTime: TimeInterval = 1.5

    func start() {
        hotkeys.onPress = { [weak self] in self?.shortcutPressed() }
        hotkeys.onRelease = { [weak self] in self?.panel.endKeyRepeat() }
        applyShortcut()

        searchModel.onActivate = { [weak self] entry in self?.activate(entry) }
        observers.isPanelVisible = { [weak self] in self?.panel.isVisible ?? false }
        searchModel.onDismiss = { [weak self] in self?.panel.dismiss(restorePrevious: true) }
        panel.onOpenSettings = { [weak self] in self?.openSettingsHandler?() }

        menuBar.onOpenSwoop = { [weak self] in self?.showPanel() }
        menuBar.onOpenSettings = { [weak self] in self?.openSettingsHandler?() }
        menuBar.onOpenPermissions = { [weak self] in self?.openOnboardingHandler?() }
        menuBar.onReportProblem = { [weak self] in self?.reportProblem() }
        menuBar.onSaveDiagnostics = { [weak self] in
            guard let self else { return }
            Task { await DiagnosticsReport.saveAndReveal(self) }
        }
        menuBar.onSuggestFeature = { NSWorkspace.shared.open(AppLinks.newIssue(.featureRequest)) }
        menuBar.shortcutDisplay = { [weak self] in self?.settings.effectiveShortcut?.displayString ?? "" }
        menuBar.isAccessibilityTrusted = { [weak self] in self?.permissions.isAccessibilityTrusted ?? false }
        supportPrompt.anchorFrame = { [weak self] in self?.menuBar.statusItemFrame }
        #if DEBUG
        menuBar.debugMenu = { [unowned self] in DebugActions.menu(self) }
        #endif

        permissions.onChange = { [weak self] trusted in
            guard let self else { return }
            log.info("accessibility trusted=\(trusted)")
            if trusted {
                onAccessibilityGranted?()
                observers.start()
                Task { await self.registry.refresh() }
            } else {
                // Revoked while running: stop AX work, drop cached elements, explain.
                observers.stop()
                panel.dismiss(restorePrevious: true)
                Task { await self.registry.refresh() } // clears entries when untrusted
                openOnboardingHandler?()
            }
        }

        if permissions.isAccessibilityTrusted {
            observers.start()
            Task { await registry.refresh() }
        }
        if !permissions.isAccessibilityTrusted || !settings.onboardingCompleted {
            openOnboardingHandler?()
        }
    }

    /// (Re)registers the global shortcut from settings. Old registration is removed first.
    func applyShortcut() {
        do {
            try hotkeys.register(settings.effectiveShortcut)
            shortcutError = nil
        } catch {
            shortcutError = error.description
            log.error("shortcut: \(error.description, privacy: .public)")
        }
    }

    /// GitHub's bug report form, pre-filled with version, system and layout (no window titles).
    func openBugReport() {
        NSWorkspace.shared.open(bugReportURL)
    }

    /// Menu → Report a Problem…: offers to save a diagnostics report (revealed in Finder, to drag into
    /// the form) before opening the GitHub form.
    func reportProblem() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Report a Problem"
        alert.informativeText = """
            Swoop can save a diagnostics report and show it in Finder, so you can drag it into the report on             GitHub. It has Swoop's version and settings, this session's log and your windows' apps,             \(settings.diagnosticsIncludeTitles ? "including window titles — check it for anything private" : "without window titles").             Nothing is sent until you submit the report.
            """
        alert.addButton(withTitle: "Save Report & Open GitHub")
        alert.addButton(withTitle: "Open GitHub Only")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task {
                await DiagnosticsReport.saveAndReveal(self)
                openBugReport()
            }
        case .alertSecondButtonReturn:
            openBugReport()
        default:
            break
        }
    }

    var bugReportURL: URL {
        AppLinks.newIssue(.bugReport, fields: [
            "swoop-version": AppLinks.appVersion,
            "macos": AppLinks.systemDescription,
            "layout": settings.panelLayout.label, // matches the form's dropdown options
        ])
    }

    func togglePanel() {
        panel.isVisible ? panel.dismiss(restorePrevious: true) : showPanel()
    }

    /// Global hotkey: open, or (while open) cycle the selection.
    private func shortcutPressed() {
        if panel.isVisible {
            panel.shortcutPressed()
        } else {
            showPanel()
            // Holding the shortcut from the opening press also starts cycling; in "switch on release"
            // mode, letting go of the modifier then switches to the selection.
            if panel.isVisible {
                panel.beginKeyRepeat()
                panel.armSwitchOnRelease()
            }
        }
    }

    func showPanel() {
        permissions.refresh()
        guard permissions.isAccessibilityTrusted else {
            openOnboardingHandler?()
            return
        }
        activationTask?.cancel()
        activationTask = nil
        let pending = lastActivation.flatMap { Date().timeIntervalSince($0.at) < Self.activationSettleTime ? $0.pid : nil }
        // Cached results appear immediately; refresh in the background (PRD §14).
        panel.show(pendingFrontmost: pending)
        Task { await registry.refresh() }
    }

    private func activate(_ entry: WindowEntry) {
        guard let target = registry.target(for: entry.id) else {
            log.error("no activation target for \(entry.id, privacy: .private)")
            hud.show("“\(entry.title)” is no longer available.")
            panel.dismiss(restorePrevious: true)
            return
        }
        panel.dismiss(restorePrevious: false)
        registry.recordUse(of: entry)
        lastActivation = (target.pid, Date())
        activationTask?.cancel()
        activationTask = Task {
            let result = await activation.activate(target)
            if result == .activated { supportPrompt.recordSwitch() }
            if case .failed(let message) = result {
                log.error("activation failed: \(message, privacy: .private)")
                hud.show(message)
                await registry.refresh()
            }
        }
    }
}

/// Event-driven registry updates (no polling): workspace notifications + AX observers.
@MainActor
final class WorkspaceObserver {
    private let registry: WindowRegistry
    private let hub = AXObserverHub()
    private var tokens: [NSObjectProtocol] = []
    private var fullRefresh: Task<Void, Never>?
    private var appRefresh: [pid_t: Task<Void, Never>] = [:]
    private var focusTasks: [pid_t: Task<Void, Never>] = [:]
    /// Structural changes only trigger work while the switcher is visible.
    var isPanelVisible: () -> Bool = { false }

    init(registry: WindowRegistry, recents: RecentWindowsStore) {
        self.registry = registry
    }

    func start() {
        guard tokens.isEmpty else { return }
        syncObservers()
        hub.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .focusChanged(let pid): noteFocus(pid: pid)
            case .structureChanged(let pid): if isPanelVisible() { scheduleRefresh(pid: pid) }
            case .windowCreated(let pid, let window): registry.learnCreatedWindow(window, pid: pid)
            }
        }
        let nc = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification,
        ]
        for name in names {
            tokens.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                MainActor.assumeIsolated { self?.handle(name, pid: pid) }
            })
        }
    }

    func stop() {
        tokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        tokens = []
        hub.removeAll()
    }

    private func handle(_ name: Notification.Name, pid: pid_t?) {
        switch name {
        case NSWorkspace.didActivateApplicationNotification:
            if let pid { noteFocus(pid: pid); if isPanelVisible() { scheduleRefresh(pid: pid) } }
        case NSWorkspace.didLaunchApplicationNotification:
            syncObservers()
            // AX often isn't ready at launch; observe again shortly after.
            Task { [weak self] in try? await Task.sleep(for: .seconds(2)); self?.syncObservers(); self?.scheduleFullRefresh() }
            scheduleFullRefresh()
        case NSWorkspace.didTerminateApplicationNotification:
            syncObservers()
            scheduleFullRefresh(delay: .milliseconds(50))
        default: // active Space changed: learn anchors for windows on the new Space
            scheduleFullRefresh()
        }
    }

    private func syncObservers() {
        let pids = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .map(\.processIdentifier)
        hub.sync(with: Set(pids))
    }

    /// Records the app's focused window as most recent (MRU reflects switches made outside Swoop).
    private func noteFocus(pid: pid_t) {
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }
        focusTasks[pid]?.cancel()
        focusTasks[pid] = Task { [registry] in
            try? await Task.sleep(for: .milliseconds(120)) // coalesce focus+main notifications
            guard !Task.isCancelled else { return }
            let title = await Task.detached { AXElement.application(pid, timeout: 0.2).element(kAXFocusedWindowAttribute)?.title }.value
            if let title { registry.noteFocus(pid: pid, title: title) }
        }
    }

    func scheduleFullRefresh(delay: Duration = .milliseconds(350)) {
        fullRefresh?.cancel()
        fullRefresh = Task { [registry] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await registry.refresh()
        }
    }

    private func scheduleRefresh(pid: pid_t) {
        appRefresh[pid]?.cancel()
        appRefresh[pid] = Task { [registry] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await registry.refresh(pid: pid)
        }
    }
}
