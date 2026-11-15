import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?
    private var windows: [AnyObject] = []
    #if DEBUG
    private var debug: DebugCommands?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if Probe.run(arguments: CommandLine.arguments) { return }
        #endif
        LastExternalApp.shared.start()
        let controller = AppController()
        self.controller = controller
        let settingsWindow = SettingsWindowController(controller: controller)
        // First launch: the guided setup. Afterwards (e.g. Accessibility revoked, or "Fix" in the menu),
        // only its permissions step.
        let onboarding = HostedWindowController(title: String(localized: "Welcome to Swoop"), staysVisible: true, chromeless: true, translucent: true) { [weak controller] () -> OnboardingView in
            let c = controller!
            let model = OnboardingModel(permissionsOnly: c.settings.onboardingCompleted)
            c.onboardingModel = model
            return OnboardingView(controller: c, model: model) { [weak c] openSwoop in
                guard let c else { return }
                c.settings.onboardingCompleted = true
                c.closeOnboarding?()
                // "Swoop away": the switcher itself, once the window is gone.
                if openSwoop { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { c.showPanel() } }
            }
        }
        onboarding.onClose = { [weak controller] in
            if controller?.permissions.isAccessibilityTrusted == true { controller?.settings.onboardingCompleted = true }
            controller?.onboardingModel = nil
        }
        // Swoop theme only; Classic keeps the standard About panel.
        let about = HostedWindowController(title: String(localized: "About Swoop"), chromeless: true, translucent: true) { AboutView(updates: controller.updates) }
        controller.openAboutHandler = { about.show() }
        let closeUpdates = WindowCloser()
        let updateWindow = HostedWindowController(title: String(localized: "Software Update"), chromeless: true, translucent: true) {
            UpdateWindowView(updates: controller.updates) { closeUpdates.close?() }
        }
        closeUpdates.close = { [weak updateWindow] in updateWindow?.close() }
        controller.openUpdateWindowHandler = { updateWindow.show() }
        controller.openSettingsHandler = { settingsWindow.show() }
        controller.selectSettingsPane = { settingsWindow.select($0) }
        controller.openOnboardingHandler = { onboarding.show() }
        controller.closeOnboarding = { onboarding.close() }
        // Permission just granted while onboarding is open: bring it back to show "All set".
        controller.onAccessibilityGranted = { if onboarding.isVisible { onboarding.show() } }
        windows = [settingsWindow, onboarding, about, updateWindow]
        MainMenu.install(openSettings: #selector(openSettings), target: self)
        controller.start()
        #if DEBUG
        debug = DebugCommands(controller: controller)
        #endif
    }

    @objc private func openSettings() { controller?.openSettingsHandler?() }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.recents.flush()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.showPanel()
        return false
    }
}

/// Lets a window's content close its own window (the controller is created after the content closure).
@MainActor
private final class WindowCloser {
    var close: (() -> Void)?
}
