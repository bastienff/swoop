import AppKit
import ApplicationServices
import SwiftUI
import SwoopCore

/// Borderless key-capable panel hosting the switcher (ARCHITECTURE §5).
final class SwoopPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Visual-effect background that picks a dark HUD material or a light popover material.
final class PanelBackgroundView: NSVisualEffectView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateMaterial()
    }

    func updateMaterial() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        material = dark ? .hudWindow : .popover
    }
}

@MainActor
final class SwoopPanelController: NSObject, NSWindowDelegate {
    static let cornerRadius: CGFloat = 36

    let model: SearchViewModel
    private let settings: AppSettings
    private var panel: SwoopPanel?
    private var hosting: NSHostingView<SwoopView>?
    private var keyMonitor: Any?
    /// ⌘, while the switcher is open (the accessory app has no main menu to route it).
    var onOpenSettings: (() -> Void)?
    private var mouseMonitor: Any?
    private var keyUpMonitor: Any?
    /// Dragging the panel by its background (Settings → Appearance → Position → Draggable).
    private var dragMonitor: Any?
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    private var isDragging = false
    /// Hold-to-repeat: while the shortcut stays held, keeps stepping the selection.
    private var repeatTask: Task<Void, Never>?
    static let repeatDelay: Duration = .milliseconds(400)
    static let repeatInterval: Duration = .milliseconds(100)
    /// Switch on release (Settings → Keyboard): watches the shortcut's modifiers while the panel is open.
    private var releaseWatch: Task<Void, Never>?
    private var flagsMonitor: Any?
    static let releasePollInterval: Duration = .milliseconds(15)
    private var previousApp: NSRunningApplication?
    /// Opened right after a switch whose activation macOS may not have applied yet: if that app takes
    /// focus from the panel shortly after opening, take it back instead of dismissing.
    private var pendingActivation: (pid: pid_t, until: Date)?
    static let pendingActivationGrace: TimeInterval = 1.0
    private var targetScreen: NSScreen?
    private(set) var isVisible = false

    init(model: SearchViewModel, settings: AppSettings) {
        self.model = model
        self.settings = settings
        super.init()
    }

    // MARK: Show / hide

    func toggle() { isVisible ? dismiss(restorePrevious: true) : show() }

    /// The global shortcut was pressed. Opens the panel; while open, cycles the selection
    /// (⇧ reverses). Escape or an outside click closes it (PRD §3).
    func shortcutPressed(reverse: Bool = false) {
        guard isVisible else { show(); return }
        model.step(reverse ? -1 : 1)
        beginKeyRepeat(reverse: reverse)
        armSwitchOnRelease()
    }

    // MARK: Switch on release

    /// In "switch on release" mode, activates the selection as soon as the shortcut's modifier is
    /// released. Only armed by the shortcut (never when opened from the menu bar, where nothing is held).
    /// A bare-key shortcut has no modifier to release, so it keeps the panel open.
    func armSwitchOnRelease() {
        guard isVisible, releaseWatch == nil, settings.switcherMode == .switchOnRelease,
              let s = settings.effectiveShortcut, !s.holdModifiers.isEmpty else { return }
        // flagsChanged reaches us once the panel is key; polling covers the moment before that (and
        // releases that happen while another app still has focus). No Input Monitoring needed.
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.checkModifierRelease()
            return event
        }
        releaseWatch = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.checkModifierRelease()
                try? await Task.sleep(for: Self.releasePollInterval)
            }
        }
    }

    private func disarmSwitchOnRelease() {
        releaseWatch?.cancel()
        releaseWatch = nil
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        flagsMonitor = nil
    }

    private func checkModifierRelease() {
        guard isVisible, releaseWatch != nil, let s = settings.effectiveShortcut else { return }
        guard !s.isHeld(by: GlobalShortcutManager.modifiers(from: NSEvent.modifierFlags)) else { return }
        disarmSwitchOnRelease()
        endKeyRepeat()
        if model.selectedEntry != nil {
            model.activateSelection()
        } else {
            dismiss(restorePrevious: true)
        }
    }

    /// Starts auto-cycling after a short delay while the shortcut stays held (like key repeat, but
    /// paced by us: the Carbon hotkey doesn't repeat). Stops on key release, modifier release, or dismiss.
    func beginKeyRepeat(reverse: Bool = false) {
        repeatTask?.cancel()
        repeatTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.repeatDelay)
            while !Task.isCancelled {
                guard let self, self.isVisible, self.shortcutModifiersDown() else { return }
                self.model.step(reverse ? -1 : 1)
                try? await Task.sleep(for: Self.repeatInterval)
            }
        }
    }

    func endKeyRepeat() {
        repeatTask?.cancel()
        repeatTask = nil
    }

    /// Whether the shortcut's modifiers are still physically held (no Input Monitoring needed).
    private func shortcutModifiersDown() -> Bool {
        guard let s = settings.effectiveShortcut else { return false }
        if s.modifiers.isEmpty { return true } // bare key: rely on the key-up/release events
        return s.isHeld(by: GlobalShortcutManager.modifiers(from: NSEvent.modifierFlags))
    }

    /// `pendingFrontmost`: an app Swoop just switched to that may not be frontmost yet. It counts as
    /// the app you're in (Escape returns to it, smart order demotes its window).
    func show(pendingFrontmost: pid_t? = nil) {
        guard !isVisible else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let pendingApp = pendingFrontmost.flatMap { NSRunningApplication(processIdentifier: $0) }.flatMap { $0.isTerminated ? nil : $0 }
        previousApp = pendingApp ?? NSWorkspace.shared.frontmostApplication
        pendingActivation = pendingApp.map { ($0.processIdentifier, Date().addingTimeInterval(Self.pendingActivationGrace)) }
        model.reset()
        model.frontmostPID = previousApp?.processIdentifier
        let screen = chooseScreen()
        targetScreen = screen
        let visible = screen.visibleFrame
        model.maxPanelSize = CGSize(width: visible.width * 0.92, height: visible.height * 0.86)
        panel.appearance = settings.appearance.nsAppearance
        updateFrame(animated: false)
        isVisible = true
        observeLayout()

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = reduceMotion ? 1 : 0
        // Activate ourselves so the search field reliably receives typing; the previous app is
        // restored on dismissal without selection (PRD §9).
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        model.requestFocus()
        if !reduceMotion {
            // Short ease-out fade: starts quickly so it never feels laggy, then settles softly.
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.24
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.3, 1)
                panel.animator().alphaValue = 1
            }
        }
        installMonitors()
    }

    /// Hides the panel. When `restorePrevious`, gives focus back to the app that was active before.
    func dismiss(restorePrevious: Bool) {
        guard isVisible, let panel else { return }
        isVisible = false
        pendingActivation = nil
        endKeyRepeat()
        disarmSwitchOnRelease()
        removeMonitors()
        panel.orderOut(nil)
        model.reset()
        if restorePrevious, let prev = previousApp, !prev.isTerminated,
           prev.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            NSApp.yieldActivation(to: prev)
            prev.activate()
        }
        previousApp = nil
    }

    // MARK: Panel

    private func makePanel() -> SwoopPanel {
        let panel = SwoopPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                                  styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                                  backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        // Applies only to our own panel (never to target windows).
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.delegate = self

        let background = PanelBackgroundView()
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = Self.cornerRadius
        background.layer?.cornerCurve = .continuous
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 0.5
        background.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        background.updateMaterial()

        let hosting = NSHostingView(rootView: SwoopView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.sizingOptions = []
        background.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: background.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background
        self.hosting = hosting
        return panel
    }

    /// Re-centers and resizes the panel whenever the result layout changes (Image 1 compact behavior).
    private func observeLayout() {
        withObservationTracking {
            _ = model.layout
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isVisible else { return }
                self.updateFrame(animated: false)
                self.observeLayout()
            }
        }
    }

    private func updateFrame(animated: Bool) {
        guard let panel, let screen = targetScreen else { return }
        let layout = model.layout
        let size = CGSize(width: layout.panelWidth.rounded(), height: layout.panelHeight.rounded())
        let v = screen.visibleFrame
        // Centered horizontally; slightly above vertical center, like the references.
        // Centered horizontally, slightly above vertical center (like the references), unless the user
        // dragged it somewhere on this display. It stays centered on that point as it grows/shrinks.
        var center = CGPoint(x: v.midX, y: v.midY + v.height * 0.06)
        if settings.panelDraggable, let saved = settings.panelCenter(display: Self.displayID(screen)) {
            center = CGPoint(x: v.minX + saved.x * v.width, y: v.minY + saved.y * v.height)
        }
        var origin = CGPoint(x: (center.x - size.width / 2).rounded(), y: (center.y - size.height / 2).rounded())
        // Always fully on screen.
        origin.x = min(max(origin.x, v.minX), max(v.maxX - size.width, v.minX))
        origin.y = min(max(origin.y, v.minY), max(v.maxY - size.height, v.minY))
        let frame = NSRect(origin: origin, size: size)
        if panel.frame != frame {
            panel.setFrame(frame, display: true, animate: animated)
            panel.invalidateShadow()
        }
    }

    private func chooseScreen() -> NSScreen {
        let screens = NSScreen.screens
        switch settings.panelDisplay {
        case .primary:
            return screens.first ?? NSScreen.main!
        case .mouseCursor:
            let p = NSEvent.mouseLocation
            return screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main ?? screens[0]
        case .activeWindow:
            if let point = focusedWindowCenterInCocoaCoordinates() {
                return screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main ?? screens[0]
            }
            let p = NSEvent.mouseLocation
            return screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main ?? screens[0]
        }
    }

    /// Center of the frontmost app's focused window, converted from AX (top-left origin) to Cocoa.
    private func focusedWindowCenterInCocoaCoordinates() -> CGPoint? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let ax = AXElement.application(app.processIdentifier, timeout: 0.1)
        guard let w = ax.element(kAXFocusedWindowAttribute),
              let posV = w.value(kAXPositionAttribute), let sizeV = w.value(kAXSizeAttribute) else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(posV as! AXValue, .cgPoint, &pos), AXValueGetValue(sizeV as! AXValue, .cgSize, &size) else { return nil }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: pos.x + size.width / 2, y: primaryHeight - (pos.y + size.height / 2))
    }

    // MARK: Input

    private func installMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible, event.window === self.panel else { return event }
            return self.handleKey(event) ? nil : event
        }
        // Releasing the shortcut key ends hold-to-repeat (when we, not Carbon, receive the key events).
        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self, let s = self.settings.effectiveShortcut, event.keyCode == s.keyCode else { return event }
            self.endKeyRepeat()
            return event
        }
        installDragMonitor()
        // Outside clicks while another app keeps focus (e.g. clicks on the desktop / menu bar).
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.settings.dismissOnOutsideClick else { return }
                self.dismiss(restorePrevious: false)
            }
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let keyUpMonitor { NSEvent.removeMonitor(keyUpMonitor) }
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
        dragMonitor = nil
        dragStart = nil
        isDragging = false
        keyMonitor = nil
        mouseMonitor = nil
        keyUpMonitor = nil
    }

    /// Returns true if the event was consumed.
    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // The global shortcut pressed again while open (Carbon may not see it while we're key):
        // cycles the selection; with ⇧ added it cycles backwards.
        if let s = settings.effectiveShortcut, event.keyCode == s.keyCode {
            let pressed = GlobalShortcutManager.modifiers(from: flags)
            // System key repeat is ignored; our own paced repeat runs instead.
            if event.isARepeat, pressed.isSuperset(of: s.modifiers) { return true }
            if pressed == s.modifiers {
                shortcutPressed()
                return true
            }
            if !s.modifiers.contains(.shift), pressed == s.modifiers.union(.shift) {
                shortcutPressed(reverse: true)
                return true
            }
        }
        // ⌘, opens Settings, like in any Mac app. Matched by character so it works on every keyboard layout.
        if flags == .command, event.charactersIgnoringModifiers == "," {
            dismiss(restorePrevious: false)
            onOpenSettings?()
            return true
        }
        switch Int(event.keyCode) {
        case 53: dismiss(restorePrevious: true); return true                 // Escape
        case 36, 76: model.activateSelection(); return true                  // Return / Enter
        case 123: model.move(.left); return true
        case 124: model.move(.right); return true
        case 125: model.move(.down); return true
        case 126: model.move(.up); return true
        case 48: model.step(flags.contains(.shift) ? -1 : 1); return true    // Tab / ⇧Tab
        default: return false
        }
    }

    // MARK: NSWindowDelegate

    // MARK: Dragging

    /// Starts a window drag only after the mouse moved a few points, and never from the search field, so
    /// clicks still switch windows and dragging in the field still selects text.
    private func installDragMonitor() {
        guard settings.panelDraggable else { return }
        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel else { return event }
            switch event.type {
            case .leftMouseDown:
                let hit = panel.contentView?.hitTest(event.locationInWindow)
                let inText = hit is NSText || hit is NSTextField || hit?.superview is NSTextField
                self.dragStart = inText ? nil : (NSEvent.mouseLocation, panel.frame.origin)
                self.isDragging = false
                return event
            case .leftMouseDragged:
                guard let start = self.dragStart else { return event }
                let p = NSEvent.mouseLocation
                let dx = p.x - start.mouse.x, dy = p.y - start.mouse.y
                if !self.isDragging && hypot(dx, dy) < 4 { return event }
                self.isDragging = true
                panel.setFrameOrigin(NSPoint(x: start.origin.x + dx, y: start.origin.y + dy))
                return nil
            case .leftMouseUp:
                defer { self.dragStart = nil }
                guard self.isDragging else { return event }
                self.isDragging = false
                self.rememberPosition()
                return nil // a drag is not a click
            default:
                return event
            }
        }
    }

    /// Saves where the panel was left, relative to the display it's on.
    private func rememberPosition() {
        guard let panel, let screen = panel.screen ?? targetScreen else { return }
        targetScreen = screen
        let v = screen.visibleFrame
        settings.setPanelCenter(CGPoint(x: (panel.frame.midX - v.minX) / v.width, y: (panel.frame.midY - v.minY) / v.height),
                                display: Self.displayID(screen))
        updateFrame(animated: false) // snap fully on screen if it was dragged past an edge
    }

    static func displayID(_ screen: NSScreen) -> String {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? screen.localizedName
    }

    func windowDidResignKey(_ notification: Notification) {
        // The previous switch's activation landed after the panel opened: that's not the user leaving.
        if isVisible, let pending = pendingActivation, Date() < pending.until, let panel,
           NSWorkspace.shared.frontmostApplication?.processIdentifier == pending.pid {
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
            model.requestFocus()
            return
        }
        // Another app took focus (click outside). Don't steal focus back.
        guard isVisible, settings.dismissOnOutsideClick else { return }
        dismiss(restorePrevious: false)
    }
}
