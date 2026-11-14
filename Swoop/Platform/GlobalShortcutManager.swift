import AppKit
import Carbon.HIToolbox
import OSLog
import SwoopCore

/// Registers one global hotkey with Carbon `RegisterEventHotKey` (ARCHITECTURE §4, F12).
/// Needs neither Input Monitoring nor Accessibility.
@MainActor
final class GlobalShortcutManager {
    enum RegistrationError: Error, Equatable, CustomStringConvertible {
        case alreadyTaken
        case failed(OSStatus)
        var description: String {
            switch self {
            case .alreadyTaken: String(localized: "Another app already uses this shortcut.")
            case .failed(let s): String(localized: "The shortcut couldn't be registered (error \(s)).", comment: "%d is an error code")
            }
        }
    }

    private static let signature: OSType = 0x5357_5443 // 'SWTC'
    private let log = Logger(subsystem: "com.bastienff.swoop", category: "hotkey")
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private(set) var current: Shortcut?
    var onPress: (() -> Void)?
    /// The hotkey's key was released (ends hold-to-repeat cycling).
    var onRelease: (() -> Void)?

    init() {
        var specs = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == GlobalShortcutManager.signature else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(userData).takeUnretainedValue()
            let released = GetEventKind(event) == UInt32(kEventHotKeyReleased)
            MainActor.assumeIsolated { released ? manager.onRelease?() : manager.onPress?() }
            return noErr
        }, specs.count, &specs, me, &handlerRef)
    }

    /// Replaces any existing registration. Pass nil to disable.
    func register(_ shortcut: Shortcut?) throws(RegistrationError) {
        unregister()
        guard let shortcut else { return }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), Self.carbonModifiers(shortcut.modifiers),
                                         EventHotKeyID(signature: Self.signature, id: 1),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            log.error("RegisterEventHotKey \(shortcut.displayString, privacy: .public) failed: \(status)")
            throw status == OSStatus(eventHotKeyExistsErr) ? .alreadyTaken : .failed(status)
        }
        hotKeyRef = ref
        current = shortcut
        log.info("registered \(shortcut.displayString, privacy: .public)")
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        current = nil
    }

    /// Tests whether a shortcut can be registered right now (another app may own it).
    func probe(_ shortcut: Shortcut) -> RegistrationError? {
        if shortcut == current { return nil }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), Self.carbonModifiers(shortcut.modifiers),
                                         EventHotKeyID(signature: Self.signature, id: 99),
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { UnregisterEventHotKey(ref); return nil }
        return status == OSStatus(eventHotKeyExistsErr) ? .alreadyTaken : .failed(status)
    }

    static func carbonModifiers(_ m: Shortcut.Modifiers) -> UInt32 {
        var r: UInt32 = 0
        if m.contains(.command) { r |= UInt32(cmdKey) }
        if m.contains(.option) { r |= UInt32(optionKey) }
        if m.contains(.control) { r |= UInt32(controlKey) }
        if m.contains(.shift) { r |= UInt32(shiftKey) }
        return r
    }

    static func modifiers(from flags: NSEvent.ModifierFlags) -> Shortcut.Modifiers {
        var m: Shortcut.Modifiers = []
        if flags.contains(.command) { m.insert(.command) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.control) { m.insert(.control) }
        if flags.contains(.shift) { m.insert(.shift) }
        return m
    }
}
