import AppKit
import SwiftUI
import SwoopCore

/// Settings panes, shown as toolbar tabs in the standard macOS preferences style
/// (see `SettingsWindowController`).
enum SettingsPane: CaseIterable {
    case keyboard, appearance, behavior, permissions, advanced
    #if DEBUG
    case debug
    #endif

    var title: String {
        switch self {
        case .keyboard: String(localized: "Keyboard", comment: "Settings tab")
        case .appearance: String(localized: "Appearance", comment: "Settings tab")
        case .behavior: String(localized: "Behavior", comment: "Settings tab")
        case .permissions: String(localized: "Permissions", comment: "Settings tab")
        case .advanced: String(localized: "Advanced", comment: "Settings tab")
        #if DEBUG
        case .debug: "Debug"
        #endif
        }
    }

    var symbol: String {
        switch self {
        case .keyboard: "keyboard"
        case .appearance: "paintbrush"
        case .behavior: "gearshape"
        case .permissions: "lock.shield"
        case .advanced: "wrench.and.screwdriver"
        #if DEBUG
        case .debug: "ladybug"
        #endif
        }
    }

    @MainActor @ViewBuilder
    func content(_ controller: AppController) -> some View {
        switch self {
        case .keyboard: KeyboardSettings(controller: controller)
        case .appearance: AppearanceSettings(settings: controller.settings)
        case .behavior: BehaviorSettings(controller: controller)
        case .permissions: PermissionsSettings(controller: controller)
        case .advanced: AdvancedSettings(controller: controller)
        #if DEBUG
        case .debug: DebugSettings(controller: controller)
        #endif
        }
    }
}

// MARK: - Keyboard

private struct KeyboardSettings: View {
    let controller: AppController
    @State private var message: String?

    var body: some View {
        @Bindable var settings = controller.settings
        Form {
            Section {
                Toggle("Enable global shortcut", isOn: $settings.shortcutEnabled)
                LabeledContent("Open Swoop") {
                    HStack {
                        ShortcutRecorder(
                            shortcut: $settings.shortcut,
                            allowBareKeys: settings.allowBareTab,
                            onRecordingChange: { recording in
                                if recording { controller.hotkeys.unregister() } else { controller.applyShortcut() }
                            },
                            onRejected: { message = $0 })
                        Button("Restore Default") { settings.shortcut = .default }
                            .disabled(settings.shortcut == .default)
                    }
                }
                .disabled(!settings.shortcutEnabled)
                if let warning = conflictWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout)
                }
                if let message {
                    Label(message, systemImage: "info.circle").foregroundStyle(.secondary).font(.callout)
                }
            } footer: {
                Text("Uses a standard hotkey registration — no Input Monitoring permission is needed.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                Picker("When you release the shortcut", selection: $settings.switcherMode) {
                    ForEach(SwitcherMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.radioGroup)
            } footer: {
                Text(switcherModeFooter)
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Allow bare Tab as the shortcut", isOn: $settings.allowBareTab)
                if settings.allowBareTab {
                    Button("Use bare Tab") { settings.shortcut = Shortcut(keyCode: Shortcut.tabKeyCode, modifiers: []) }
                        .disabled(settings.shortcut.isBareTab)
                }
            } footer: {
                Text("Warning: with bare Tab, every Tab key press in every app opens Swoop instead of moving focus or indenting. Only enable this if you understand the trade-off.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.shortcut) { message = nil; controller.applyShortcut() }
        .onChange(of: settings.shortcutEnabled) { controller.applyShortcut() }
        .onChange(of: settings.allowBareTab) {
            if !settings.allowBareTab && settings.shortcut.isUnmodified { settings.shortcut = .default }
            controller.applyShortcut()
        }
    }

    private var switcherModeFooter: String {
        let s = controller.settings
        switch s.switcherMode {
        case .stayOpen:
            return String(localized: "The switcher stays open after you release the keys. Press the shortcut again to move to the next window (add ⇧ to go back); Escape closes it.")
        case .switchOnRelease:
            let hold = s.shortcut.holdModifiers.displayString
            if hold.isEmpty {
                return String(localized: "A shortcut without a modifier key can't be held, so the switcher stays open. Record a shortcut with ⌘, ⌥ or ⌃ to switch on release.")
            }
            return String(localized: "Keep \(hold) held and press the shortcut again (or keep it pressed) to move through the windows; add ⇧ to go back. Release \(hold) to switch to the selected window. Escape cancels.", comment: "%@ is a modifier key such as ⌥")
        }
    }

    private var conflictWarning: String? {
        let s = controller.settings
        if let error = controller.shortcutError { return error }
        if s.shortcut.isUnmodified && !s.allowBareTab { return String(localized: "Bare keys are disabled; the shortcut is inactive.") }
        if let known = s.shortcut.knownConflict { return String(localized: "May conflict with: \(known).", comment: "%@ is a system shortcut name") }
        return nil
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                LabeledContent("Theme") {
                    VisualPicker(options: AppTheme.allCases, selection: $settings.theme, label: \.label) {
                        ThemeThumbnail(theme: $0)
                    }
                }
                LabeledContent("Layout") {
                    VisualPicker(options: PanelLayout.allCases, selection: $settings.panelLayout, label: \.label) {
                        LayoutThumbnail(layout: $0)
                    }
                }
                if !settings.panelLayout.isList {
                    LabeledContent("Icon size") {
                        VisualPicker(options: IconSize.allCases, selection: $settings.iconSize, label: \.label) {
                            IconSizeThumbnail(size: $0)
                        }
                    }
                }
                LabeledContent("Appearance") {
                    VisualPicker(options: AppearanceMode.allCases, selection: $settings.appearance, label: \.label) {
                        AppearanceThumbnail(mode: $0)
                    }
                }
                if settings.panelLayout.isList {
                    Stepper("Maximum visible rows: \(settings.maxVisibleListRows)", value: $settings.maxVisibleListRows, in: 3...20)
                } else {
                    Stepper("Maximum visible rows: \(settings.maxVisibleRows)", value: $settings.maxVisibleRows, in: 1...8)
                }
            }
            Section {
                Picker("Show on", selection: $settings.panelDisplay) {
                    ForEach(PanelDisplay.allCases) { Text($0.label).tag($0) }
                }
                LabeledContent("Position") {
                    HStack(spacing: 10) {
                        if settings.panelDraggable && !settings.panelPositions.isEmpty {
                            Button("Reset") { settings.resetPanelPositions() }
                                .help("Open in the center again")
                        }
                        Picker("Position", selection: Binding(get: { settings.panelDraggable ? PanelPositionMode.draggable : .centered },
                                                              set: { settings.panelDraggable = $0 == .draggable })) {
                            ForEach(PanelPositionMode.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                Toggle("Always show the search field", isOn: $settings.alwaysShowSearchField)
            } footer: {
                Text(settings.panelDraggable
                     ? String(localized: "Drag the switcher by its background; it reopens where you left it on each display. The search field appears as soon as you type when it's hidden.")
                     : String(localized: "The search field appears as soon as you type when it's hidden."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Behavior

private struct BehaviorSettings: View {
    let controller: AppController
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginError: String?

    var body: some View {
        @Bindable var settings = controller.settings
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) {
                        loginError = LaunchAtLogin.set(launchAtLogin)?.localizedDescription
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                if let loginError { Text(loginError).font(.footnote).foregroundStyle(.red) }
                Toggle("Dismiss when clicking outside", isOn: $settings.dismissOnOutsideClick)
            }
            Section {
                Picker("Order windows by", selection: $settings.windowOrder) {
                    ForEach(WindowOrder.allCases) { Text($0.label).tag($0) }
                }
            } footer: {
                Text(settings.windowOrder.explanation)
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Windows") {
                Toggle("Show minimized windows", isOn: $settings.showMinimized)
                Toggle("Include full-screen windows", isOn: $settings.includeFullScreen)
                Toggle("Discover native window tabs", isOn: $settings.nativeTabDiscovery)
                Toggle(isOn: $settings.recoverOtherSpaceWindows) {
                    Text("Remember windows on other desktops")
                    Text("Keeps windows on desktops you visited reachable after Swoop restarts. Uses non-public macOS accessibility functions; turn off if a macOS update misbehaves.")
                }
            }
            Section("Visual Studio Code") {
                Toggle("Show project names", isOn: $settings.vscodeEnhancements)
                Toggle("Boost project-name matches in search", isOn: $settings.vscodeSearchBoost)
            }
            Section {
                Toggle("Check for updates automatically", isOn: $settings.checkForUpdates)
                if settings.checkForUpdates {
                    Picker("Check", selection: $settings.updateFrequency) {
                        ForEach(UpdatePolicy.Frequency.allCases) { Text($0.label).tag($0) }
                    }
                }
                LabeledContent("Version \(UpdateChecker.currentVersion)") {
                    UpdateStatusView(checker: controller.updates)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("Swoop connects to the internet only to check for updates, and only if you allow it: when you click Check for Updates, or on the schedule above with automatic checks on. It asks GitHub for the latest version number; nothing about you or your windows is sent.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.showMinimized) { refresh() }
        .onChange(of: settings.includeFullScreen) { refresh() }
        .onChange(of: settings.nativeTabDiscovery) { refresh() }
        .onChange(of: settings.recoverOtherSpaceWindows) { refresh() }
        .onChange(of: settings.vscodeEnhancements) { refresh() }
        .onChange(of: settings.checkForUpdates) { controller.updates.applySetting() }
        .onChange(of: settings.updateFrequency) { controller.updates.applySetting(restart: true) }
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }

    private func refresh() { Task { await controller.registry.refresh() } }
}

// MARK: - Permissions

struct PermissionsSettings: View {
    let controller: AppController

    var body: some View {
        let p = controller.permissions
        Form {
            Section {
                PermissionRow(title: "Accessibility", granted: p.isAccessibilityTrusted, required: true,
                              detail: "Required to list windows, read their titles and native tabs, and focus the exact window you pick.")
                if !p.isAccessibilityTrusted {
                    HStack {
                        Button("Request Access") { p.requestAccessibility() }
                        Button("Open System Settings") { p.openAccessibilitySettings() }
                    }
                }
            }
            Section("Not needed") {
                PermissionRow(title: "Input Monitoring", granted: nil, required: false,
                              detail: "Not requested. The global shortcut uses a standard hotkey registration that doesn't read your keystrokes.")
                PermissionRow(title: "Screen Recording", granted: nil, required: false,
                              detail: "Not requested. Swoop shows app icons, not window previews.")
            }
        }
        .formStyle(.grouped)
        .onAppear { p.refresh(); p.startWatching() }
        .onDisappear { p.stopWatching() }
    }
}

struct PermissionRow: View {
    let title: LocalizedStringKey
    let granted: Bool?
    let required: Bool
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: granted == true ? "checkmark.circle.fill" : granted == false ? "xmark.octagon.fill" : "minus.circle")
                .foregroundStyle(granted == true ? .green : granted == false ? .red : .secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title).font(.headline)
                    if let granted { Text(granted ? "Granted" : "Not granted" as LocalizedStringKey).foregroundStyle(.secondary) }
                }
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Advanced

private struct AdvancedSettings: View {
    let controller: AppController
    @State private var status = ""

    var body: some View {
        @Bindable var settings = controller.settings
        Form {
            Section {
                Toggle("Debug logging", isOn: $settings.debugLogging)
                Button("Refresh Window Registry") {
                    Task { await controller.registry.refresh(); status = String(localized: "Refreshed: \(controller.registry.entries.count) windows.") }
                }
                Button("Reset Recent Usage") { controller.recents.reset(); status = String(localized: "Recent usage cleared.") }
                if !status.isEmpty { Text(status).font(.footnote).foregroundStyle(.secondary) }
            } footer: {
                Text("Debug logging writes the window list, with titles, to the system log (subsystem com.bastienff.swoop).")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Diagnostics") {
                Toggle("Include window titles in reports", isOn: $settings.diagnosticsIncludeTitles)
                HStack {
                    Button("Save Diagnostics Report…") {
                        Task {
                            if let url = await DiagnosticsReport.saveAndReveal(controller) { status = String(localized: "Saved \(url.lastPathComponent).", comment: "%@ is a file name") }
                        }
                    }
                    Button("Show Reports Folder") {
                        try? FileManager.default.createDirectory(at: DiagnosticsReport.folder, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(DiagnosticsReport.folder)
                    }
                }
                Text("Attach the report to a bug report on GitHub. It has Swoop's version, settings and this session's log, and lists your windows' apps; titles are left out unless you include them. It stays on this Mac until you attach it.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button("Quit Swoop", role: .destructive) { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
    }
}

/// Swoop theme for a Settings pane: brand background behind the form, form
/// background hidden, orange switches and picture-picker selection. Classic: no change at all.
struct SettingsThemeStyle: ViewModifier {
    let settings: AppSettings
    let chrome: SettingsChrome

    // One view tree for both themes (no if/else): switching themes only flips modifier values. A branch swap
    // rebuilds the form's scroll view, and a fresh one flashes its scroll bar (with "Show scroll bars: Always")
    // before `.never` applies.
    func body(content: Content) -> some View {
        let swoop = settings.theme == .swoop
        content
            .scrollContentBackground(swoop ? .hidden : .automatic)
            // Under the full-size toolbar AppKit shows a full-length scroll bar (with "Show scroll bars:
            // Always") although the pane fits; nothing scrolls. Scrolling still works if a pane doesn't fit.
            // Also hidden while the window still has that toolbar after switching to Classic (the window
            // catches up a moment after the pane).
            .scrollIndicators(swoop || chrome.fullSizeContent ? .never : .automatic)
            .background { if swoop { FittedBrandBackground().ignoresSafeArea() } }
            .environment(\.themeAccent, swoop ? Brand.orange : Color.accentColor)
            // Orange switches only: a pane-wide `.tint` also greys out menu pickers' labels.
            .toggleStyle(ThemedSwitchStyle(brand: swoop))
    }
}

/// The Settings window's actual chrome, set by its controller once the window style has changed.
@MainActor @Observable
final class SettingsChrome {
    /// Content runs under the toolbar (`.fullSizeContentView`, Swoop theme).
    var fullSizeContent = false
}

/// A standard switch, tinted with the brand orange in the Swoop theme (the tint applies to this toggle only).
struct ThemedSwitchStyle: ToggleStyle {
    let brand: Bool

    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration).toggleStyle(.switch).tint(brand ? Brand.orange : nil)
    }
}
