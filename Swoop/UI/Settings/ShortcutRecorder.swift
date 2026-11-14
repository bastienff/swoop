import AppKit
import SwiftUI
import SwoopCore

/// Click-to-record shortcut field. While recording, the global hotkey is suspended so the
/// keystroke reaches the recorder instead of opening the switcher.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    let allowBareKeys: Bool
    var onRecordingChange: (Bool) -> Void = { _ in }
    var onRejected: (String) -> Void = { _ in }
    /// Onboarding: a big key-cap style button.
    var large = false

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Type shortcut…" : shortcut.displayString)
                .font(.system(size: large ? 22 : 13, weight: large ? .semibold : .medium, design: .rounded))
                .frame(minWidth: large ? 240 : 120, minHeight: large ? 38 : nil)
        }
        .buttonStyle(.bordered)
        .controlSize(large ? .large : .regular)
        .tint(recording ? .accentColor : nil)
        .onDisappear { stop() }
        .accessibilityHint("Click, then press the new key combination. Escape cancels.")
    }

    private func start() {
        recording = true
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = GlobalShortcutManager.modifiers(from: event.modifierFlags.intersection(.deviceIndependentFlagsMask))
            if event.keyCode == 53 && mods.isEmpty { stop(); return nil } // Escape cancels
            let candidate = Shortcut(keyCode: event.keyCode, modifiers: mods)
            if let problem = Self.validate(candidate, allowBareKeys: allowBareKeys) {
                onRejected(problem)
                return nil
            }
            shortcut = candidate
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { recording = false; onRecordingChange(false) }
    }

    static func validate(_ s: Shortcut, allowBareKeys: Bool) -> String? {
        let functionKeys: Set<UInt16> = [0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F]
        if s.modifiers.isEmpty && !functionKeys.contains(s.keyCode) {
            if s.isBareTab && allowBareKeys { return nil }
            return s.isBareTab
                ? "Enable “Allow bare Tab” first: it intercepts Tab in every app."
                : "Add at least one modifier (⌘, ⌥, ⌃ or ⇧)."
        }
        if s.modifiers == [.shift] && !functionKeys.contains(s.keyCode) {
            return "Shift alone would block typing that character. Add ⌘, ⌥ or ⌃."
        }
        return nil
    }
}
