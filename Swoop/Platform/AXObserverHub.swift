import AppKit
import ApplicationServices
import OSLog

/// Per-app Accessibility observers (ARCHITECTURE §2 "Event-driven updates").
///
/// Cost policy (low idle CPU): focus changes only update recency (one cheap AX read);
/// structural and title changes refresh just that app, coalesced by `WorkspaceObserver` (titles at a
/// bounded rate), so the switcher opens already up to date. Opening the panel still refreshes everything.
@MainActor
final class AXObserverHub {
    enum Event { case focusChanged(pid_t), structureChanged(pid_t), titleChanged(pid_t), windowCreated(pid_t, AXElement) }

    private var observers: [pid_t: AXObserver] = [:]
    private let log = Logger(subsystem: "com.bastienff.swoop", category: "observers")
    var onEvent: ((Event) -> Void)?

    private static let focusNotifications = [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification]
    private static let structureNotifications = [
        kAXWindowCreatedNotification, kAXUIElementDestroyedNotification, kAXTitleChangedNotification,
        kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
    ]

    /// Synchronizes observers with the set of running regular apps.
    func sync(with pids: Set<pid_t>) {
        for pid in observers.keys where !pids.contains(pid) { remove(pid) }
        for pid in pids where observers[pid] == nil { add(pid) }
    }

    func removeAll() { for pid in Array(observers.keys) { remove(pid) } }

    /// Apps with a live observer (diagnostics: an app without one only updates when the switcher opens).
    var observedPIDs: Set<pid_t> { Set(observers.keys) }

    private func add(_ pid: pid_t) {
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let hub = Unmanaged<AXObserverHub>.fromOpaque(refcon).takeUnretainedValue()
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            let name = notification as String
            let created = name == (kAXWindowCreatedNotification as String) ? AXElement(element) : nil
            MainActor.assumeIsolated { hub.handle(name, pid: pid, created: created) }
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var registered = 0
        for n in Self.focusNotifications + Self.structureNotifications
        where AXObserverAddNotification(observer, app, n as CFString, refcon) == .success {
            registered += 1
        }
        guard registered > 0 else { return } // app not AX-capable (or not ready yet)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func remove(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    private func handle(_ notification: String, pid: pid_t, created: AXElement?) {
        if let created { onEvent?(.windowCreated(pid, created)) }
        if Self.focusNotifications.contains(notification) {
            onEvent?(.focusChanged(pid))
        } else if notification == kAXTitleChangedNotification as String {
            onEvent?(.titleChanged(pid))
        } else {
            onEvent?(.structureChanged(pid))
        }
    }
}
