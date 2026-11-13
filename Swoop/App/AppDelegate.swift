import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?
    private var windows: [AnyObject] = []
    #if DEBUG
    private var debug: DebugCommands?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Probe.run(arguments: CommandLine.arguments) { return }
        LastExternalApp.shared.start()
        let controller = AppController()
        self.controller = controller
        let settingsWindow = SettingsWindowController(controller: controller)
        let onboarding = HostedWindowController(title: "Welcome to Swoop", staysVisible: true) { [weak controller] in
            OnboardingView(controller: controller!) { [weak controller] in
                controller?.settings.onboardingCompleted = true
                controller?.closeOnboarding?()
            }
        }
        onboarding.onClose = { [weak controller] in
            if controller?.permissions.isAccessibilityTrusted == true { controller?.settings.onboardingCompleted = true }
        }
        controller.openSettingsHandler = { settingsWindow.show() }
        controller.selectSettingsPane = { settingsWindow.select($0) }
        controller.openOnboardingHandler = { onboarding.show() }
        controller.closeOnboarding = { onboarding.close() }
        // Permission just granted while onboarding is open: bring it back to show "All set".
        controller.onAccessibilityGranted = { if onboarding.isVisible { onboarding.show() } }
        windows = [settingsWindow, onboarding]
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
