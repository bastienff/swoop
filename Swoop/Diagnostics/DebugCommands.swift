#if DEBUG
import AppKit
import Carbon.HIToolbox
import SwoopCore

/// DEBUG-only remote control used to verify the running app end-to-end from scripts
/// (`Tools/swctl`). Not compiled into Release builds.
@MainActor
final class DebugCommands {
    static let name = Notification.Name("com.bastienff.swoop.debug")
    private let controller: AppController
    private var token: NSObjectProtocol?

    init(controller: AppController) {
        self.controller = controller
        token = DistributedNotificationCenter.default().addObserver(forName: Self.name, object: nil, queue: .main) { [weak self] note in
            let cmd = note.object as? String ?? ""
            MainActor.assumeIsolated { self?.handle(cmd) }
        }
    }

    private func handle(_ line: String) {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        let cmd = parts.first ?? ""
        let arg = parts.count > 1 ? parts[1] : ""
        switch cmd {
        case "show": controller.showPanel()
        case "hide": controller.panel.dismiss(restorePrevious: true)
        case "type": controller.searchModel.query = arg
        case "key": key(arg)
        case "hotkey":
            // Post the configured shortcut through the HID event stream.
            let s = controller.settings.shortcut
            Self.post(s.keyCode, s.modifiers)
        case "dump": dump(to: arg)
        case "snapshot":
            // snapshot <path> [clear]: "clear" renders only the content, on a transparent background.
            let a = arg.split(separator: " ").map(String.init)
            snapshot(to: a.first ?? "", clear: a.count > 1 && a[1] == "clear")
        case "demo": loadDemo()
        case "draggable": controller.settings.panelDraggable = arg == "on"
        case "mode": controller.settings.switcherMode = SwitcherMode(rawValue: arg) ?? .stayOpen
        case "timecensus":
            var c0 = clock(), t0 = ProcessInfo.processInfo.systemUptime
            for _ in 0..<20 { _ = WindowCensus.current() }
            var out = String(format: "census: wall %.1f ms, cpu %.1f ms\n", (ProcessInfo.processInfo.systemUptime - t0) / 20 * 1000, Double(clock() - c0) / Double(CLOCKS_PER_SEC) / 20 * 1000)
            c0 = clock(); t0 = ProcessInfo.processInfo.systemUptime
            for _ in 0..<20 { _ = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) }
            out += String(format: "zorder list: wall %.1f ms, cpu %.1f ms", (ProcessInfo.processInfo.systemUptime - t0) / 20 * 1000, Double(clock() - c0) / Double(CLOCKS_PER_SEC) / 20 * 1000)
            try? out.write(toFile: arg, atomically: true, encoding: .utf8)
        case "releasemods":
            // releasemods: release every modifier (clears a latched modifier state after synthetic events).
            let src = CGEventSource(stateID: .hidSystemState)
            for code: CGKeyCode in [55, 56, 58, 59] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)
                e?.flags = []
                e?.post(tap: .cghidEventTap)
            }
        case "cmdtab":
            // cmdtab: a real ⌘Tab (macOS app switcher) through the HID event stream.
            let src = CGEventSource(stateID: .hidSystemState)
            func send(_ code: CGKeyCode, _ down: Bool, _ flags: CGEventFlags) {
                let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
                e?.flags = flags
                e?.post(tap: .cghidEventTap)
            }
            send(55, true, .maskCommand); send(48, true, .maskCommand); send(48, false, .maskCommand)
            Task { try? await Task.sleep(for: .milliseconds(150)); send(55, false, []) }
        case "clickat":
            // clickat <x> <y>: a real left click at global top-left coordinates.
            let a = arg.split(separator: " ").compactMap { Double($0) }
            guard a.count == 2 else { break }
            let p = CGPoint(x: a[0], y: a[1])
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        case "timerefresh":
            // timerefresh <outfile> <app name>: average one-app refresh time over 20 runs (+ CPU time).
            let parts = arg.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2, let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == parts[1] }) else { break }
            Task { @MainActor in
                let cpu0 = ProcessInfo.processInfo.systemUptime, c0 = clock()
                for _ in 0..<20 { await controller.registry.refresh(pid: app.processIdentifier) }
                let wall = (ProcessInfo.processInfo.systemUptime - cpu0) / 20 * 1000
                let cpu = Double(clock() - c0) / Double(CLOCKS_PER_SEC) / 20 * 1000
                try? String(format: "%@: wall %.1f ms, cpu %.1f ms per refresh", parts[1], wall, cpu).write(toFile: parts[0], atomically: true, encoding: .utf8)
            }
        case "report":
            // report <path>: writes a diagnostics report to <path>.
            Task { @MainActor in try? await DiagnosticsReport.make(controller).write(toFile: arg, atomically: true, encoding: .utf8) }
        case "bugurl": try? controller.bugReportURL.absoluteString.write(toFile: arg, atomically: true, encoding: .utf8)
        case "searchfield": controller.settings.alwaysShowSearchField = arg == "always"
        case "order": controller.settings.windowOrder = WindowOrder(rawValue: arg) ?? .smart
        case "results":
            // results <path>: the switcher's current order (as if opened now), top 5.
            let m = controller.searchModel
            m.frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let top = m.results.prefix(5).map { "\($0.appName) | \($0.title)" }.joined(separator: "\n")
            try? top.write(toFile: arg, atomically: true, encoding: .utf8)
        case "dragpanel":
            // dragpanel <dx> <dy>: real mouse drag from the panel's bottom-left padding (exercises the drag path).
            let a = arg.split(separator: " ").compactMap { Double($0) }
            guard a.count == 2, let w = NSApp.windows.first(where: { $0 is SwoopPanel && $0.isVisible }),
                  let primary = NSScreen.screens.first else { break }
            let startCocoa = NSPoint(x: w.frame.minX + 14, y: w.frame.minY + 10)
            let toCG = { (p: NSPoint) in CGPoint(x: p.x, y: primary.frame.height - p.y) } // CG: top-left origin
            let start = toCG(startCocoa)
            Task { @MainActor in
                func post(_ type: CGEventType, _ p: CGPoint) {
                    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
                }
                post(.leftMouseDown, start)
                for i in 1...10 {
                    try? await Task.sleep(for: .milliseconds(16))
                    post(.leftMouseDragged, CGPoint(x: start.x + a[0] * Double(i) / 10, y: start.y - a[1] * Double(i) / 10))
                }
                post(.leftMouseUp, CGPoint(x: start.x + a[0], y: start.y - a[1]))
            }
        case "panelframe":
            if let w = NSApp.windows.first(where: { $0 is SwoopPanel && $0.isVisible }) {
                try? "\(Int(w.frame.minX)) \(Int(w.frame.minY)) \(Int(w.frame.width)) \(Int(w.frame.height))"
                    .write(toFile: arg, atomically: true, encoding: .utf8)
            }
        case "layout":
            // layout grid|compact|comfortable
            let map: [String: PanelLayout] = ["grid": .grid, "compact": .compactList, "comfortable": .comfortableList]
            if let l = map[arg] { controller.settings.panelLayout = l }
        case "onboarding":
            // onboarding [full]: "full" shows the first-run setup again (resets the completed flag).
            if arg == "full" { controller.closeOnboarding?(); controller.settings.onboardingCompleted = false }
            controller.openOnboardingHandler?()
        case "onboardingdenied":
            // onboardingdenied on|off: preview the "not granted" permissions state.
            controller.onboardingModel?.previewNotGranted = arg != "off"
        case "onboardingstep":
            // onboardingstep <index>: jump to a step of the open onboarding.
            if let i = Int(arg) { controller.onboardingModel?.go(to: i) }
        case "supportcard":
            // supportcard [png]: shows the support card; optionally captures it (dark fill behind).
            controller.supportPrompt.show()
            if !arg.isEmpty {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    guard let v = NSApp.windows.first(where: { $0.isVisible && $0.level == .floating && $0.title.isEmpty })?.contentView,
                          let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
                    v.cacheDisplay(in: v.bounds, to: rep)
                    let img = NSImage(size: v.bounds.size)
                    img.lockFocus()
                    NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.16, alpha: 1).setFill()
                    NSBezierPath(roundedRect: v.bounds, xRadius: 18, yRadius: 18).fill()
                    rep.draw(in: v.bounds)
                    img.unlockFocus()
                    if let t = img.tiffRepresentation, let png = NSBitmapImageRep(data: t)?.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: arg))
                    }
                }
            }
        case "setshortcut":
            // setshortcut <keyCode> <mods: subset of "cosx" = cmd opt shift ctrl>
            let a = arg.split(separator: " ")
            if let code = UInt16(a.first ?? "") {
                controller.settings.shortcut = Shortcut(keyCode: code, modifiers: Self.mods(a.count > 1 ? String(a[1]) : ""))
                controller.applyShortcut()
            }
        case "post":
            let a = arg.split(separator: " ")
            if let code = UInt16(a.first ?? "") { Self.post(code, Self.mods(a.count > 1 ? String(a[1]) : "")) }
        case "hold":
            // hold <ms>: press ⌥, hold Tab for <ms>, release both (exercises hold-to-repeat cycling).
            let ms = Int(arg) ?? 1000
            Task { @MainActor in
                let src = CGEventSource(stateID: .hidSystemState)
                func send(_ code: CGKeyCode, _ down: Bool, _ flags: CGEventFlags) {
                    let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
                    e?.flags = flags
                    e?.post(tap: .cghidEventTap)
                }
                send(58, true, .maskAlternate)
                send(48, true, .maskAlternate)
                try? await Task.sleep(for: .milliseconds(ms))
                send(48, false, .maskAlternate)
                send(58, false, [])
            }
        case "settings":
            controller.openSettingsHandler?()
            if let i = Int(arg) { controller.selectSettingsPane?(i) }
        case "snapwin":
            // snapwin <path> <title prefix>
            let a = arg.split(separator: " ", maxSplits: 1).map(String.init)
            if a.count == 2, let w = NSApp.windows.first(where: { $0.title.hasPrefix(a[1]) && $0.isVisible }),
               let v = w.contentView?.superview ?? w.contentView {
                if let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                    v.cacheDisplay(in: v.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: a[0]))
                }
            }
        case "appearance": controller.settings.appearance = AppearanceMode(rawValue: arg) ?? .system
        case "refresh": Task { await controller.registry.refresh() }
        case "select":
            // select <substring>: selects the first visible result whose title/app contains it.
            if let e = controller.searchModel.results.first(where: { "\($0.appName) \($0.title)".localizedCaseInsensitiveContains(arg) }) {
                controller.searchModel.selectedID = e.id
            }
        default: break
        }
    }

    static func mods(_ s: String) -> Shortcut.Modifiers {
        var m: Shortcut.Modifiers = []
        if s.contains("c") { m.insert(.command) }
        if s.contains("o") { m.insert(.option) }
        if s.contains("s") { m.insert(.shift) }
        if s.contains("x") { m.insert(.control) }
        return m
    }

    static func post(_ keyCode: UInt16, _ m: Shortcut.Modifiers) {
        let src = CGEventSource(stateID: .hidSystemState)
        var flags: CGEventFlags = []
        if m.contains(.option) { flags.insert(.maskAlternate) }
        if m.contains(.command) { flags.insert(.maskCommand) }
        if m.contains(.control) { flags.insert(.maskControl) }
        if m.contains(.shift) { flags.insert(.maskShift) }
        // Press and release the modifier keys too, like a real keyboard: flags alone leave the system's
        // modifier state latched (NSEvent.modifierFlags keeps reporting them as held).
        let modifierKeys: [(Shortcut.Modifiers, CGKeyCode, CGEventFlags)] = [
            (.control, 59, .maskControl), (.option, 58, .maskAlternate), (.shift, 56, .maskShift), (.command, 55, .maskCommand)]
        let pressed = modifierKeys.filter { m.contains($0.0) }
        func send(_ code: CGKeyCode, _ down: Bool, _ f: CGEventFlags) {
            let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
            e?.flags = f
            e?.post(tap: .cghidEventTap)
        }
        var held: CGEventFlags = []
        for (_, code, flag) in pressed { held.insert(flag); send(code, true, held) }
        send(CGKeyCode(keyCode), true, flags)
        send(CGKeyCode(keyCode), false, flags)
        for (_, code, flag) in pressed.reversed() { held.remove(flag); send(code, false, held) }
    }

    private func key(_ name: String) {
        let m = controller.searchModel
        switch name {
        case "left": m.move(.left)
        case "right": m.move(.right)
        case "up": m.move(.up)
        case "down": m.move(.down)
        case "return": m.activateSelection()
        case "escape": controller.panel.dismiss(restorePrevious: true)
        default: break
        }
    }

    private func dump(to path: String) {
        let m = controller.searchModel
        var s = controller.registry.dump()
        s += "\n--- panel visible=\(controller.panel.isVisible) query=\"\(m.query)\" results=\(m.results.count) "
        let l = m.layout
        s += "layout cols=\(l.columns) rows=\(l.rows) visibleRows=\(l.visibleRows) size=\(Int(l.panelWidth))x\(Int(l.panelHeight))\n"
        s += "selected=\(m.selectedEntry.map { "\($0.appName) | \($0.title)" } ?? "nil")\n"
        s += "frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")\n"
        s += "shortcut=\(controller.settings.effectiveShortcut?.displayString ?? "none") error=\(controller.shortcutError ?? "none")\n"
        for (i, e) in m.results.enumerated() { s += "  [\(i)] \(e.appName) | \(e.subtitle)\n" }
        try? s.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Renders the panel's own view hierarchy (no Screen Recording needed). Background blur is not
    /// captured by cacheDisplay, so a dark fill is composited behind it.
    private func loadDemo() { Self.loadDemo(into: controller.registry) }

    /// Generic demo windows (no real titles) using icons of apps installed on this Mac.
    static func loadDemo(into registry: WindowRegistry) {
        typealias W = WindowRegistry.DemoWindow
        let code = "/Applications/Visual Studio Code.app"
        registry.loadDemo([
            W(appPath: "/Applications/Slack.app", appName: "Slack", title: "general (Channel) - Larkspur - Slack", badge: "2"),
            W(appPath: "/System/Applications/Notes.app", appName: "Notes", title: "Notes – 42 notes", minimized: true),
            W(appPath: "/Applications/DBeaver.app", appName: "DBeaver", title: "DBeaver 26.2.3", otherDesktop: true),
            W(appPath: "/Applications/Postman.app", appName: "Postman", title: "https://api.example.com/v1/flights"),
            W(appPath: "/Applications/ChatGPT.app", appName: "ChatGPT", title: "Explain Swift actors"),
            W(appPath: "/Applications/Ghostty.app", appName: "Ghostty", title: "~/code/heron-web"),
            W(appPath: "/Applications/Ghostty.app", appName: "Ghostty", title: "π - kestrel-api — zsh"),
            W(appPath: code, appName: "Code", title: "README.md — heron-web", tab: true),
            W(appPath: code, appName: "Code", title: "server.ts — kestrel-api", otherDesktop: true),
            W(appPath: code, appName: "Code", title: ".env — osprey-auth", tab: true, otherDesktop: true),
            W(appPath: code, appName: "Code", title: "Untitled-1 — wren-ui"),
            W(appPath: code, appName: "Code", title: "schema.prisma — finch-billing"),
            W(appPath: code, appName: "Code", title: "App.tsx — robin-mobile"),
            W(appPath: code, appName: "Code", title: "main.tf — owl-infra"),
            W(appPath: code, appName: "Code", title: "index.md — egret-docs"),
            W(appPath: code, appName: "Code", title: "routes.go — plover-search"),
            W(appPath: code, appName: "Code", title: "Dockerfile — tern-notify"),
            W(appPath: code, appName: "Code", title: "pre-push — dove-config"),
            W(appPath: code, appName: "Code", title: "worker.py — gull-pipeline"),
            W(appPath: code, appName: "Code", title: "Package.swift — puffin-sdk"),
            W(appPath: code, appName: "Code", title: "styles.css — lark-site"),
            W(appPath: "/Applications/Brave Browser.app", appName: "Brave Browser", title: "Pull requests · larkspur/heron-web"),
            W(appPath: "/Applications/OrbStack.app", appName: "OrbStack", title: "Containers"),
            W(appPath: "/Applications/Spark.app", appName: "Spark", title: "Inbox"),
            W(appPath: "/System/Applications/Preview.app", appName: "Preview", title: "sample-invoice.pdf"),
            W(appPath: "/Applications/Microsoft Excel.app", appName: "Microsoft Excel", title: "Sample Budget.xlsx"),
        ])
    }

    private func snapshot(to path: String, clear: Bool = false) {
        guard let content = NSApp.windows.first(where: { $0 is SwoopPanel && $0.isVisible })?.contentView else { return }
        let view = clear ? (content.subviews.first ?? content) : content
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        if clear { // full backing resolution, alpha preserved
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            return
        }
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        let dark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if !clear {
            (dark ? NSColor(calibratedRed: 0.13, green: 0.13, blue: 0.17, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: SwoopPanelController.cornerRadius, yRadius: SwoopPanelController.cornerRadius).fill()
        }
        rep.draw(in: bounds)
        image.unlockFocus()
        if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }
}
#endif
