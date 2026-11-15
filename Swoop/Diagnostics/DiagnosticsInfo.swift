import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Darwin
import IOKit
import Security
import ServiceManagement

/// Facts about the Mac and Swoop's install for the diagnostics report: the things outside Swoop that
/// most often explain "the shortcut does nothing", "it didn't switch desktop" or "a window is missing".
/// Read-only, public APIs, nothing personal (no window titles, home folder shown as ~).
@MainActor
enum DiagnosticsInfo {

    // MARK: Install

    static var installLines: [String] {
        let path = Bundle.main.bundlePath
        var lines = ["App: \(tildePath(path))"]
        if path.contains("/AppTranslocation/") {
            lines.append("  ⚠ Translocated: macOS runs it from a temporary copy (moved out of Downloads/DMG without Finder). Permissions may not stick.")
        } else if !path.hasPrefix("/Applications/") {
            lines.append("  Not in /Applications")
        }
        lines.append("Signature: \(signature)")
        let others = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .map(\.standardizedFileURL.path).filter { $0 != URL(fileURLWithPath: path).standardizedFileURL.path }
        lines.append("Other copies of Swoop: " + (others.isEmpty ? "none" : others.map(tildePath).joined(separator: ", ")))
        let brew = ["/opt/homebrew/Caskroom/swoop", "/usr/local/Caskroom/swoop"].contains { FileManager.default.fileExists(atPath: $0) }
        lines.append("Homebrew cask: \(brew ? "installed" : "no")")
        lines.append("Launch at login: \(loginItemStatus)")
        return lines
    }

    /// Signing kind and team: the Accessibility grant is tied to it (an ad-hoc build loses it on every rebuild).
    static var signature: String {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return "unknown" }
        let flags = (dict[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        if flags & 0x2 != 0 { return "ad-hoc (Accessibility must be granted again after each update)" } // kSecCodeSignatureAdhoc
        let certs = dict[kSecCodeInfoCertificates as String] as? [SecCertificate]
        // "Developer ID Application: Name (TEAM)" → keep the kind only.
        let kind = certs?.first.flatMap { SecCertificateCopySubjectSummary($0) as String? }?
            .split(separator: ":").first.map(String.init) ?? "signed"
        let team = dict[kSecCodeInfoTeamIdentifier as String] as? String
        return kind + (team.map { ", team \($0)" } ?? "")
    }

    static var loginItemStatus: String {
        switch SMAppService.mainApp.status {
        case .enabled: "on"
        case .notRegistered: "off"
        case .requiresApproval: "waiting for approval in System Settings → General → Login Items"
        case .notFound: "off (not found)"
        @unknown default: "unknown"
        }
    }

    // MARK: Keyboard

    /// Secure keyboard entry (password fields, some terminals and password managers) can keep global
    /// shortcuts from reaching Swoop while it's on.
    static var secureInput: String {
        guard IsSecureEventInputEnabled() else { return "off" }
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        let users = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [[String: Any]]
        let pid = users?.lazy.compactMap { ($0["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value }.first
        let owner = pid.flatMap { NSRunningApplication(processIdentifier: $0) }
        let name = owner?.bundleIdentifier ?? owner?.localizedName ?? pid.map { "pid \($0)" } ?? "unknown app"
        return "ON, held by \(name) (global shortcuts may not reach Swoop until it's turned off)"
    }

    /// Keyboard layout and current input source: shortcuts are registered by key code, so layouts matter.
    static var inputSources: String {
        func id(_ source: TISInputSource?) -> String? {
            guard let source, let p = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
            return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
        }
        let layout = id(TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()) ?? "?"
        let input = id(TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()) ?? "?"
        return input == layout ? layout : "\(layout) (input source \(input))"
    }

    // MARK: macOS settings

    /// System settings that change how switching between desktops behaves.
    static var systemSettingLines: [String] {
        func value(_ key: String, _ domain: String) -> Any? {
            CFPreferencesCopyAppValue(key as CFString, domain as CFString)
        }
        func flag(_ key: String, _ domain: String, default d: Bool) -> String {
            guard let v = value(key, domain) as? NSNumber else { return "\(d ? "on" : "off") (default)" }
            return v.boolValue ? "on" : "off"
        }
        let global = kCFPreferencesAnyApplication as String
        let ws = NSWorkspace.shared
        return [
            "When switching to an app, switch to a desktop with its windows: \(flag("AppleSpacesSwitchOnActivate", global, default: true))",
            "Automatically rearrange desktops by recent use: \(flag("mru-spaces", "com.apple.dock", default: true))",
            "Displays have separate desktops: \(NSScreen.screensHaveSeparateSpaces ? "on" : "off")",
            "Stage Manager: \(flag("GloballyEnabled", "com.apple.WindowManager", default: false))",
            "Prefer tabs when opening documents: \((value("AppleWindowTabbingMode", global) as? String) ?? "fullscreen (default)")",
            "Reduce motion: \(ws.accessibilityDisplayShouldReduceMotion), reduce transparency: \(ws.accessibilityDisplayShouldReduceTransparency), increase contrast: \(ws.accessibilityDisplayShouldIncreaseContrast)",
            "System appearance: \(NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light")",
            "Language: \(Locale.preferredLanguages.prefix(3).joined(separator: ", ")), region \(Locale.current.region?.identifier ?? "?"), Swoop shown in \(Bundle.main.preferredLocalizations.first ?? "?")",
        ]
    }

    // MARK: Other apps

    /// Running apps known to grab shortcuts, manage windows/desktops or change displays — frequent causes
    /// of conflicts. Matched by process name against a fixed list; nothing else about other processes is read.
    static var relatedApps: [String] {
        let known: [String: String] = [
            "AltTab": "window switcher", "Witch": "window switcher", "witchdaemon": "window switcher",
            "Contexts": "window switcher", "HyperSwitch": "window switcher", "DockDoor": "window switcher",
            "Mission Control Plus": "window switcher", "Raycast": "launcher", "Alfred": "launcher",
            "BetterTouchTool": "shortcuts", "Keyboard Maestro Engine": "shortcuts", "Hammerspoon": "shortcuts",
            "karabiner_grabber": "keyboard remapper", "Karabiner-Menu": "keyboard remapper", "Hyperkey": "keyboard remapper",
            "skhd": "shortcuts", "yabai": "window manager", "AeroSpace": "window manager", "Amethyst": "window manager",
            "Rectangle": "window manager", "Rectangle Pro": "window manager", "Magnet": "window manager",
            "Moom": "window manager", "Divvy": "window manager", "Loop": "window manager", "Swish": "window manager",
            "BetterSnapTool": "window manager", "Spaceman": "desktops", "BetterDisplay": "displays",
        ]
        var found: [String: String] = [:]
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let n = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        var name = [CChar](repeating: 0, count: 256)
        for pid in pids.prefix(Int(max(n, 0))) where pid > 0 {
            guard proc_name(pid, &name, UInt32(name.count)) > 0 else { continue }
            let s = String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if let kind = known[s] { found[s] = kind }
        }
        return found.sorted { $0.key < $1.key }.map { "\($0.key) (\($0.value))" }
    }

    // MARK: Swoop process

    static var processLine: String {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        let peakMB = Int(usage.ru_maxrss) / 1_048_576 // bytes on macOS
        let p = ProcessInfo.processInfo
        let thermal = switch p.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "?"
        }
        return "CPU time \(String(format: "%.1f", cpu)) s, peak memory \(peakMB) MB, Mac up \(duration(p.systemUptime)), thermal \(thermal), low power \(p.isLowPowerModeEnabled)"
    }

    // MARK: Helpers

    static func appVersion(_ app: NSRunningApplication?) -> String? {
        guard let url = app?.bundleURL, let info = Bundle(url: url)?.infoDictionary else { return nil }
        return info["CFBundleShortVersionString"] as? String ?? info["CFBundleVersion"] as? String
    }

    /// Electron apps expose windows through Chromium's AX layer, with their own quirks.
    static func isElectron(_ app: NSRunningApplication?) -> Bool {
        guard let url = app?.bundleURL else { return false }
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path)
    }

    static func axErrorName(_ e: AXError) -> String {
        switch e {
        case .cannotComplete: "cannotComplete: busy or not responding"
        case .apiDisabled: "apiDisabled: no Accessibility access"
        case .notImplemented: "notImplemented: app has no Accessibility support"
        case .attributeUnsupported: "attributeUnsupported"
        case .noValue: "noValue"
        case .invalidUIElement: "invalidUIElement"
        case .failure: "failure"
        default: "\(e.rawValue)"
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86_400 { return "\(s / 3600)h \(s % 3600 / 60)m" }
        return "\(s / 86_400)d \(s % 86_400 / 3600)h"
    }

    static func tildePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
