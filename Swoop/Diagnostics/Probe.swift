import AppKit
import ApplicationServices
import Carbon
import Foundation

#if DEBUG

/// Diagnostic experiments used to validate platform assumptions on a real desktop.
/// Invoked via `open Swoop.app --args --probe <command> <out-file> [args...]`.
/// Output is plain text written to <out-file>. Not part of the user-facing flow. DEBUG builds only.
@MainActor
enum Probe {
    private static var out = ""
    private static func log(_ s: String) { out += s + "\n" }

    /// Private symbol, used here ONLY to correlate AX and CG data during diagnosis.
    private typealias GetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private static let getWindow: GetWindowFn? = {
        guard let h = dlopen(nil, RTLD_NOW), let s = dlsym(h, "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(s, to: GetWindowFn.self)
    }()

    static func run(arguments: [String]) -> Bool {
        guard let i = arguments.firstIndex(of: "--probe"), arguments.count > i + 2 else { return false }
        let cmd = arguments[i + 1], path = arguments[i + 2]
        let rest = Array(arguments.dropFirst(i + 3))
        log("probe \(cmd) \(rest) at \(Date()) AXTrusted=\(AXIsProcessTrusted())")
        let finish: @MainActor @Sendable () -> Void = {
            try? out.write(toFile: path, atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
        switch cmd {
        case "prompt":
            let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            log("trusted=\(AXIsProcessTrustedWithOptions(opts))")
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { MainActor.assumeIsolated { finish() } }
        case "menus":
            dumpMenus(filter: rest.first)
            finish()
        case "pressmenu":
            // pressmenu <pid> <exact title> <order: press|activate+press|press+activate>
            pressMenu(pid: pid_t(rest[0])!, title: rest[1], order: rest[2], done: finish)
        case "tour":
            // tour <seconds>: record onscreen windows on every active-Space change
            tour(seconds: Double(rest.first ?? "45") ?? 45, done: finish)
        case "twostep":
            // twostep <pid> <target tab title>
            twoStep(pid: pid_t(rest[0])!, title: rest[1], done: finish)
        case "windows":
            dumpWindows(filter: rest.first)
            finish()
        case "activate":
            // activate <pid> <cgWindowID> <strategy>
            activate(pid: pid_t(rest[0])!, wid: CGWindowID(rest[1])!, strategy: rest[2], done: finish)
        case "presstab":
            // presstab <pid> <tab title substring>
            pressTab(pid: pid_t(rest[0])!, title: rest[1], done: finish)
        case "hotkey":
            hotkeyTest(done: finish)
        case "attrs":
            // attrs <bundle id substring>: attribute names/values of Window-menu items and tab buttons
            dumpAttrs(filter: rest[0])
            finish()
        case "elem":
            // elem <bundle id substring> <element id>: describe one element reached by remote token (read-only)
            describeRemote(filter: rest[0], id: UInt64(rest[1]) ?? 0)
            finish()
        case "remotescan":
            // remotescan <bundle id substring> <seconds> [maxId]
            remoteScan(filter: rest[0], seconds: Double(rest[1]) ?? 20, maxId: rest.count > 2 ? UInt64(rest[2]) : nil)
            finish()
        default:
            log("unknown command"); finish()
        }
        return true
    }

    // MARK: - Helpers

    static func attr(_ e: AXUIElement, _ a: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil
    }
    static func str(_ e: AXUIElement, _ a: String) -> String { (attr(e, a) as? String) ?? "<nil>" }
    static func elems(_ e: AXUIElement, _ a: String) -> [AXUIElement] { (attr(e, a) as? [AXUIElement]) ?? [] }
    static func wid(_ e: AXUIElement) -> CGWindowID {
        var id: CGWindowID = 0
        _ = getWindow?(e, &id)
        return id
    }
    static func point(_ e: AXUIElement, _ a: String) -> CGPoint? {
        guard let v = attr(e, a) else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
    }

    static func cgWindows() -> [[String: Any]] {
        (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
    }

    static func describeTree(_ e: AXUIElement, depth: Int, maxDepth: Int) {
        let role = str(e, kAXRoleAttribute)
        let pad = String(repeating: "  ", count: depth)
        let interesting = ["AXTabGroup", "AXRadioButton", "AXTab", "AXButton"].contains(role) || depth <= 1
        if interesting {
            log("\(pad)\(role) sub=\(str(e, kAXSubroleAttribute)) title=\(str(e, kAXTitleAttribute)) value=\(attr(e, kAXValueAttribute).map { "\($0)" } ?? "<nil>") desc=\(str(e, kAXDescriptionAttribute))")
        }
        guard depth < maxDepth else { return }
        for c in elems(e, kAXChildrenAttribute) { describeTree(c, depth: depth + 1, maxDepth: maxDepth) }
    }

    // MARK: - windows

    static func dumpWindows(filter: String?) {
        let cg = cgWindows()
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let f = filter, !(app.bundleIdentifier ?? "").contains(f) { continue }
            let pid = app.processIdentifier
            let axApp = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(axApp, 1.0)
            let t0 = Date()
            let wins = elems(axApp, kAXWindowsAttribute)
            let dt = Date().timeIntervalSince(t0)
            log("\n=== \(app.localizedName ?? "?") [\(app.bundleIdentifier ?? "?")] pid=\(pid) AXWindows=\(wins.count) (\(Int(dt * 1000))ms)")
            log("  focusedWindow=\(attr(axApp, kAXFocusedWindowAttribute).map { str($0 as! AXUIElement, kAXTitleAttribute) } ?? "<nil>")")
            var axIDs = Set<CGWindowID>()
            for w in wins {
                let id = wid(w); axIDs.insert(id)
                log("  AX wid=\(id) role=\(str(w, kAXRoleAttribute)) sub=\(str(w, kAXSubroleAttribute)) title=\"\(str(w, kAXTitleAttribute))\" min=\(attr(w, kAXMinimizedAttribute).map { "\($0)" } ?? "?") main=\(attr(w, kAXMainAttribute).map { "\($0)" } ?? "?") fullscreen=\(attr(w, "AXFullScreen").map { "\($0)" } ?? "?") pos=\(point(w, kAXPositionAttribute).map { "\($0)" } ?? "?") doc=\(str(w, kAXDocumentAttribute))")
                // Look for native tab groups (direct children of the window).
                for c in elems(w, kAXChildrenAttribute) where str(c, kAXRoleAttribute) == "AXTabGroup" {
                    log("    TABGROUP sub=\(str(c, kAXSubroleAttribute)) desc=\(str(c, kAXDescriptionAttribute))")
                    for t in elems(c, kAXChildrenAttribute) {
                        log("      tab role=\(str(t, kAXRoleAttribute)) sub=\(str(t, kAXSubroleAttribute)) title=\"\(str(t, kAXTitleAttribute))\" value=\(attr(t, kAXValueAttribute).map { "\($0)" } ?? "<nil>") actions=\(actions(t))")
                    }
                }
            }
            let cgForPid = cg.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
            for w in cgForPid {
                let id = w[kCGWindowNumber as String] as! CGWindowID
                let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
                log("  CG wid=\(id) onscreen=\(w[kCGWindowIsOnscreen as String] ?? false) inAX=\(axIDs.contains(id)) \(b["Width"] ?? 0)x\(b["Height"] ?? 0) @\(b["X"] ?? 0),\(b["Y"] ?? 0)")
            }
        }
    }

    static func actions(_ e: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(e, &names) == .success else { return [] }
        return (names as? [String]) ?? []
    }

    // MARK: - menus

    static func dumpMenus(filter: String?) {
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let f = filter, !(app.bundleIdentifier ?? "").contains(f) { continue }
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(axApp, 1.0)
            guard let bar = attr(axApp, kAXMenuBarAttribute) else { log("\n=== \(app.localizedName ?? "?") no menubar"); continue }
            let tops = elems(bar as! AXUIElement, kAXChildrenAttribute)
            log("\n=== \(app.localizedName ?? "?") [\(app.bundleIdentifier ?? "?")] menus=\(tops.map { str($0, kAXTitleAttribute) })")
            // Dump the last three top-level menus (Window menu is normally second-to-last).
            for top in tops.suffix(3) {
                log("  MENU \(str(top, kAXTitleAttribute)) id=\(str(top, "AXIdentifier"))")
                for menu in elems(top, kAXChildrenAttribute) {
                    for item in elems(menu, kAXChildrenAttribute) {
                        let t = str(item, kAXTitleAttribute)
                        if t.isEmpty { continue }
                        log("    item \"\(t)\" id=\(str(item, "AXIdentifier")) mark=\(str(item, "AXMenuItemMarkChar")) enabled=\(attr(item, kAXEnabledAttribute).map { "\($0)" } ?? "?") cmd=\(str(item, "AXMenuItemCmdChar"))")
                    }
                }
            }
        }
    }

    static func windowMenuItems(_ axApp: AXUIElement) -> [AXUIElement] {
        guard let bar = attr(axApp, kAXMenuBarAttribute) else { return [] }
        var result: [AXUIElement] = []
        for top in elems(bar as! AXUIElement, kAXChildrenAttribute) {
            for menu in elems(top, kAXChildrenAttribute) {
                result += elems(menu, kAXChildrenAttribute).filter { str($0, "AXIdentifier") == "makeKeyAndOrderFront:" }
            }
        }
        return result
    }

    static func onscreenIDs(pid: pid_t) -> [CGWindowID: String] {
        var r: [CGWindowID: String] = [:]
        for w in cgWindows() where (w[kCGWindowOwnerPID as String] as? Int32) == pid && (w[kCGWindowLayer as String] as? Int) == 0 {
            let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
            r[w[kCGWindowNumber as String] as! CGWindowID] = "on=\(w[kCGWindowIsOnscreen as String] as? Bool ?? false) \(b["X"] ?? 0),\(b["Y"] ?? 0) \(b["Width"] ?? 0)x\(b["Height"] ?? 0)"
        }
        return r
    }

    static func pressMenu(pid: pid_t, title: String, order: String, done: @escaping @MainActor @Sendable () -> Void) {
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 1.0)
        var t = title; var index = 0
        if let at = title.lastIndex(of: "@"), let n = Int(title[title.index(after: at)...]) { t = String(title[..<at]); index = n }
        let matches = windowMenuItems(axApp).filter { t.hasPrefix("~") ? str($0, kAXTitleAttribute).contains(t.dropFirst()) : str($0, kAXTitleAttribute) == t }
        guard matches.count > index else { log("menu item not found"); done(); return }
        let item = matches[index]
        let app = NSRunningApplication(processIdentifier: pid)!
        let before = onscreenIDs(pid: pid)
        let visibleBefore = Set(elems(axApp, kAXWindowsAttribute).map { wid($0) })
        log("SIG before: \(onscreenSignature())")
        for step in order.split(separator: "+") {
            if step == "press" { log("  AXPress menu item -> \(AXUIElementPerformAction(item, kAXPressAction as CFString).rawValue)") }
            if step == "activate" { log("  activate() -> \(app.activate())") }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            MainActor.assumeIsolated {
                log("SIG after:  \(onscreenSignature())  front=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
                let after = onscreenIDs(pid: pid)
                let fw = attr(axApp, kAXFocusedWindowAttribute).map { $0 as! AXUIElement }
                let fid = fw.map { wid($0) } ?? 0
                log("focused window id=\(fid) title=\"\(fw.map { str($0, kAXTitleAttribute) } ?? "")\" titleMatches=\(fw.map { str($0, kAXTitleAttribute) == title } ?? false)")
                log("focused window CG before: \(before[fid] ?? "absent")")
                log("focused window CG after:  \(after[fid] ?? "absent")")
                log("was in AXWindows before (i.e. on original Space)? \(visibleBefore.contains(fid))")
                log("AXWindows now: \(elems(axApp, kAXWindowsAttribute).map { "\(wid($0)) \"\(str($0, kAXTitleAttribute))\"" })")
                done()
            }
        }
    }

    static func onscreenSignature() -> String {
        cgWindows().filter {
            ($0[kCGWindowIsOnscreen as String] as? Bool) == true && ($0[kCGWindowLayer as String] as? Int) == 0
                && (($0[kCGWindowBounds as String] as? [String: Any])?["Height"] as? Double ?? 0) > 100
        }.map { "\($0[kCGWindowOwnerName as String] ?? "?")#\($0[kCGWindowNumber as String] ?? 0)" }.sorted().joined(separator: ", ")
    }

    nonisolated(unsafe) static var tourObserver: NSObjectProtocol?
    static func tour(seconds: Double, done: @escaping @MainActor @Sendable () -> Void) {
        log("start: \(onscreenSignature())")
        tourObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                MainActor.assumeIsolated { log("space change: \(onscreenSignature())") }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated { done() } }
    }

    static func twoStep(pid: pid_t, title: String, done: @escaping @MainActor @Sendable () -> Void) {
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 1.0)
        let app = NSRunningApplication(processIdentifier: pid)!
        log("SIG start: \(onscreenSignature())")
        guard let main = attr(axApp, kAXMainWindowAttribute).map({ $0 as! AXUIElement }) else { log("no main window"); done(); return }
        log("main window: \(wid(main)) \"\(str(main, kAXTitleAttribute))\"")
        log("  AXMain -> \(AXUIElementSetAttributeValue(main, kAXMainAttribute as CFString, kCFBooleanTrue).rawValue)")
        log("  AXRaise -> \(AXUIElementPerformAction(main, kAXRaiseAction as CFString).rawValue)")
        log("  activate -> \(app.activate())")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            MainActor.assumeIsolated {
                log("SIG after step1: \(onscreenSignature())")
                var pressed = false
                for w in elems(axApp, kAXWindowsAttribute) {
                    for g in elems(w, kAXChildrenAttribute) where str(g, kAXRoleAttribute) == "AXTabGroup" {
                        for t in elems(g, kAXChildrenAttribute) where str(t, kAXTitleAttribute) == title {
                            log("  press tab -> \(AXUIElementPerformAction(t, kAXPressAction as CFString).rawValue)")
                            pressed = true
                        }
                    }
                }
                if !pressed { log("  tab not found on this Space") }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    MainActor.assumeIsolated {
                        let fw = attr(axApp, kAXFocusedWindowAttribute).map { $0 as! AXUIElement }
                        log("SIG after step2: \(onscreenSignature()) focused=\"\(fw.map { str($0, kAXTitleAttribute) } ?? "nil")\"")
                        done()
                    }
                }
            }
        }
    }

    // MARK: - activate

    static func snapshotState(_ label: String, pid: pid_t, wid target: CGWindowID) {
        let front = NSWorkspace.shared.frontmostApplication
        let axApp = AXUIElementCreateApplication(pid)
        let fw = attr(axApp, kAXFocusedWindowAttribute).map { $0 as! AXUIElement }
        let onscreen = cgWindows().filter { ($0[kCGWindowIsOnscreen as String] as? Bool) == true && ($0[kCGWindowLayer as String] as? Int) == 0 }
            .map { "\($0[kCGWindowOwnerName as String] ?? "?")#\($0[kCGWindowNumber as String] ?? 0)" }
        let targetCG = cgWindows().first { ($0[kCGWindowNumber as String] as? CGWindowID) == target }
        log("[\(label)] front=\(front?.localizedName ?? "?") focusedWin=\(fw.map { "\(wid($0)) \"\(str($0, kAXTitleAttribute))\"" } ?? "nil") targetOnscreen=\(targetCG?[kCGWindowIsOnscreen as String] ?? false) targetBounds=\(targetCG?[kCGWindowBounds as String] ?? "?")")
        log("   onscreen: \(onscreen.joined(separator: ", "))")
    }

    static func activate(pid: pid_t, wid target: CGWindowID, strategy: String, done: @escaping @MainActor @Sendable () -> Void) {
        let axApp = AXUIElementCreateApplication(pid)
        let candidates = elems(axApp, kAXWindowsAttribute) + [kAXFocusedWindowAttribute, kAXMainWindowAttribute].compactMap { attr(axApp, $0).map { $0 as! AXUIElement } }
        guard let w = candidates.first(where: { target == 0 || wid($0) == target }) else {
            log("target window \(target) not found in AXWindows"); done(); return
        }
        log("target title=\"\(str(w, kAXTitleAttribute))\" strategy=\(strategy)")
        snapshotState("before", pid: pid, wid: target)
        let app = NSRunningApplication(processIdentifier: pid)!
        let parts = strategy.split(separator: "+").map(String.init)
        for step in parts {
            switch step {
            case "main": log("  set AXMain -> \(AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue).rawValue)")
            case "focus": log("  set AXFocused -> \(AXUIElementSetAttributeValue(w, kAXFocusedAttribute as CFString, kCFBooleanTrue).rawValue)")
            case "raise": log("  AXRaise -> \(AXUIElementPerformAction(w, kAXRaiseAction as CFString).rawValue)")
            case "unmin": log("  unminimize -> \(AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanFalse).rawValue)")
            case "activate": log("  activate() -> \(app.activate())")
            case "activateAll": log("  activate(allWindows) -> \(app.activate(options: [.activateAllWindows]))")
            case "frontmost": log("  set app AXFrontmost -> \(AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue).rawValue)")
            case "openapp": NSWorkspace.shared.openApplication(at: app.bundleURL!, configuration: .init()); log("  openApplication")
            default: log("  unknown step \(step)")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            MainActor.assumeIsolated {
                snapshotState("after1.5s", pid: pid, wid: target)
                done()
            }
        }
    }

    // MARK: - native tab press

    static func pressTab(pid: pid_t, title: String, done: @escaping @MainActor @Sendable () -> Void) {
        let axApp = AXUIElementCreateApplication(pid)
        for w in elems(axApp, kAXWindowsAttribute) {
            for g in elems(w, kAXChildrenAttribute) where str(g, kAXRoleAttribute) == "AXTabGroup" {
                for t in elems(g, kAXChildrenAttribute) where str(t, kAXTitleAttribute).contains(title) {
                    log("found tab \"\(str(t, kAXTitleAttribute))\" in window \(wid(w)) \"\(str(w, kAXTitleAttribute))\"")
                    snapshotState("before", pid: pid, wid: wid(w))
                    log("  AXPress -> \(AXUIElementPerformAction(t, kAXPressAction as CFString).rawValue)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        MainActor.assumeIsolated {
                            let wins = elems(axApp, kAXWindowsAttribute)
                            log("after: AXWindows=\(wins.map { "\(wid($0)) \"\(str($0, kAXTitleAttribute))\"" })")
                            log("after: focused=\(attr(axApp, kAXFocusedWindowAttribute).map { str($0 as! AXUIElement, kAXTitleAttribute) } ?? "nil")")
                            done()
                        }
                    }
                    return
                }
            }
        }
        log("tab not found"); done()
    }

    // MARK: - hotkey

    nonisolated(unsafe) static var hotkeyFired = 0
    nonisolated(unsafe) static var tapSaw = 0

    static func hotkeyTest(done: @escaping @MainActor @Sendable () -> Void) {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in Probe.hotkeyFired += 1; return noErr }, 1, &spec, nil, nil)
        var ref: EventHotKeyRef?
        let st = RegisterEventHotKey(UInt32(kVK_Tab), UInt32(optionKey), EventHotKeyID(signature: 0x53575443, id: 1), GetApplicationEventTarget(), 0, &ref)
        log("RegisterEventHotKey(⌥Tab) = \(st)")
        // Post a synthetic ⌥Tab through the HID stream.
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Tab), keyDown: down)
            e?.flags = .maskAlternate
            e?.post(tap: .cghidEventTap)
        }
        log("posted synthetic ⌥Tab; waiting 8s (also press ⌥Tab manually)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            MainActor.assumeIsolated {
                log("carbon hotkey fired \(Probe.hotkeyFired) time(s)")
                done()
            }
        }
    }

    // MARK: - remotescan

    private typealias CreateFn = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    private typealias TokenFn = @convention(c) (AXUIElement) -> Unmanaged<CFData>?

    /// Measures the AXUIElementID layout of an app: ids of windows we can already see, then a timed
    /// sweep from 0 recording every AXWindow root reachable through a remote token.
    static func remoteScan(filter: String, seconds: Double, maxId: UInt64?) {
        guard let h = dlopen(nil, RTLD_NOW),
              let c = dlsym(h, "_AXUIElementCreateWithRemoteToken"), let t = dlsym(h, "_AXUIElementRemoteTokenCreate") else {
            log("symbols missing"); return
        }
        let create = unsafeBitCast(c, to: CreateFn.self), token = unsafeBitCast(t, to: TokenFn.self)
        func elementID(_ e: AXUIElement) -> UInt64? {
            guard let d = token(e)?.takeRetainedValue(), CFDataGetLength(d) == 20 else { return nil }
            var id: UInt64 = 0
            withUnsafeMutableBytes(of: &id) { CFDataGetBytes(d, CFRange(location: 12, length: 8), $0.baseAddress!.assumingMemoryBound(to: UInt8.self)) }
            return id
        }
        guard let app = NSWorkspace.shared.runningApplications.first(where: { ($0.bundleIdentifier ?? "").contains(filter) }) else { log("no app"); return }
        let pid = app.processIdentifier
        log("app \(app.localizedName ?? "?") pid=\(pid) launched=\(app.launchDate.map { "\($0)" } ?? "?")")
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 1.0)
        for w in elems(axApp, kAXWindowsAttribute) {
            log("  visible id=\(elementID(w).map(String.init) ?? "?") wid=\(wid(w)) title=\"\(str(w, kAXTitleAttribute))\"")
        }
        for a in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            if let w = attr(axApp, a) { let w = w as! AXUIElement; log("  \(a) id=\(elementID(w).map(String.init) ?? "?") wid=\(wid(w)) title=\"\(str(w, kAXTitleAttribute))\"") }
        }
        for a in [kAXMainWindowAttribute] {
            if let w = attr(axApp, a) {
                for b in [kAXCloseButtonAttribute, kAXZoomButtonAttribute, kAXMinimizeButtonAttribute] {
                    if let e = attr(w as! AXUIElement, b) { log("  main.\(b) id=\(elementID(e as! AXUIElement).map(String.init) ?? "?")") }
                }
            }
        }
        // A brand-new element (fresh query) approximates the current id high-water mark.
        if let mb = attr(axApp, kAXMenuBarAttribute) { log("  menubar id=\(elementID(mb as! AXUIElement).map(String.init) ?? "?")") }
        let cgWids = Set(cgWindows().filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
            .compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
        log("  CG wids: \(cgWids.sorted())")

        var bytes = [UInt8](repeating: 0, count: 20)
        var p = pid, magic = Int32(0x636f636f)
        withUnsafeBytes(of: &p) { for i in 0..<4 { bytes[i] = $0[i] } }
        withUnsafeBytes(of: &magic) { for i in 0..<4 { bytes[8 + i] = $0[i] } }
        let t0 = Date()
        var id: UInt64 = 0, hits = 0, misses = 0, lastHit: UInt64 = 0
        var seenWids = Set<CGWindowID>()
        while Date().timeIntervalSince(t0) < seconds, maxId.map({ id <= $0 }) ?? true {
            var v = id
            withUnsafeBytes(of: &v) { for i in 0..<8 { bytes[12 + i] = $0[i] } }
            let data = CFDataCreate(nil, bytes, 20)!
            if let e = create(data)?.takeRetainedValue() {
                AXUIElementSetMessagingTimeout(e, 0.1)
                var w: CGWindowID = 0
                if Probe.getWindow?(e, &w) == .success, w != 0 {
                    hits += 1; lastHit = id
                    if !seenWids.contains(w), str(e, kAXRoleAttribute) == kAXWindowRole as String {
                        seenWids.insert(w)
                        log("  HIT id=\(id) wid=\(w) sub=\(str(e, kAXSubroleAttribute)) inCG=\(cgWids.contains(w)) title=\"\(str(e, kAXTitleAttribute))\" t=\(Int(Date().timeIntervalSince(t0) * 1000))ms")
                    }
                } else { misses += 1 }
            }
            id += 1
        }
        let dt = Date().timeIntervalSince(t0)
        var touched: [UInt64] = []
        func walk(_ e: AXUIElement, _ d: Int) { if d > 3 { return }; for c in elems(e, kAXChildrenAttribute) { if let i = elementID(c) { touched.append(i) }; walk(c, d + 1) } }
        for w in elems(axApp, kAXWindowsAttribute) { walk(w, 0) }
        log("touched \(touched.count) descendants, ids \(touched.min() ?? 0)...\(touched.max() ?? 0)")
        log("swept 0..<\(id) in \(Int(dt * 1000))ms (\(Int(Double(id) / dt)) ids/s); element hits=\(hits) lastHit=\(lastHit) windows=\(seenWids.count)")
    }

    static func dumpAttrs(filter: String) {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { ($0.bundleIdentifier ?? "").contains(filter) }) else { return }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 1.0)
        func describe(_ e: AXUIElement, _ label: String) {
            var names: CFArray?
            AXUIElementCopyAttributeNames(e, &names)
            log("\(label):")
            for n in (names as? [String]) ?? [] {
                let v = attr(e, n)
                let d: String = if let v, CFGetTypeID(v) == AXUIElementGetTypeID() { "element role=\(str(v as! AXUIElement, kAXRoleAttribute)) title=\(str(v as! AXUIElement, kAXTitleAttribute)) wid=\(wid(v as! AXUIElement))" } else { String(describing: v).prefix(80).description }
                log("  \(n) = \(d)")
            }
            var p: CFArray?
            AXUIElementCopyParameterizedAttributeNames(e, &p)
            log("  params: \((p as? [String]) ?? [])  actions: \(actions(e))")
        }
        if let bar = attr(axApp, kAXMenuBarAttribute) {
            outer: for top in elems(bar as! AXUIElement, kAXChildrenAttribute).reversed() {
                for m in elems(top, kAXChildrenAttribute) {
                    let items = elems(m, kAXChildrenAttribute).filter { str($0, "AXIdentifier") == "makeKeyAndOrderFront:" }
                    if let i = items.first { describe(i, "menu item"); break outer }
                }
            }
        }
        if let w = attr(axApp, kAXMainWindowAttribute) {
            for c in elems(w as! AXUIElement, kAXChildrenAttribute) where str(c, kAXRoleAttribute) == "AXTabGroup" {
                describe(c, "tab group")
                if let t = elems(c, kAXChildrenAttribute).first { describe(t, "tab button") }
            }
        }
    }

    static func describeRemote(filter: String, id: UInt64) {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { ($0.bundleIdentifier ?? "").contains(filter) }),
              let h = dlopen(nil, RTLD_NOW), let c = dlsym(h, "_AXUIElementCreateWithRemoteToken") else { return }
        let create = unsafeBitCast(c, to: CreateFn.self)
        var bytes = [UInt8](repeating: 0, count: 20)
        var p = app.processIdentifier, magic = Int32(0x636f636f), v = id
        withUnsafeBytes(of: &p) { for i in 0..<4 { bytes[i] = $0[i] } }
        withUnsafeBytes(of: &magic) { for i in 0..<4 { bytes[8 + i] = $0[i] } }
        withUnsafeBytes(of: &v) { for i in 0..<8 { bytes[12 + i] = $0[i] } }
        guard let e = create(CFDataCreate(nil, bytes, 20)!)?.takeRetainedValue() else { log("no element"); return }
        AXUIElementSetMessagingTimeout(e, 1.0)
        var names: CFArray?
        AXUIElementCopyAttributeNames(e, &names)
        log("element id=\(id) wid=\(wid(e))")
        for n in (names as? [String]) ?? [] where n != "AXChildren" && n != "AXChildrenInNavigationOrder" {
            let v = attr(e, n)
            let d: String = if let v, CFGetTypeID(v) == AXUIElementGetTypeID() { "element role=\(str(v as! AXUIElement, kAXRoleAttribute)) title=\(str(v as! AXUIElement, kAXTitleAttribute)) wid=\(wid(v as! AXUIElement))" } else { String(describing: v).prefix(100).description }
            log("  \(n) = \(d)")
        }
        log("  actions: \(actions(e))")
        for c in elems(e, kAXChildrenAttribute) {
            log("  child \(str(c, kAXRoleAttribute)) sub=\(str(c, kAXSubroleAttribute)) title=\(str(c, kAXTitleAttribute))")
            if str(c, kAXRoleAttribute) == "AXTabGroup" {
                for t in elems(c, kAXChildrenAttribute) { log("    tab \(str(t, kAXTitleAttribute)) value=\(attr(t, kAXValueAttribute).map { "\($0)" } ?? "nil")") }
            }
        }
    }
}
#endif
