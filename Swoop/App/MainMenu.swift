import AppKit

/// An invisible main menu. Swoop is a menu-bar app (no Dock icon, no menu bar of its own), but macOS
/// delivers the standard shortcuts through the main menu: without it ⌘A, ⌘C, ⌘V, ⌘X and ⌘Z do nothing in
/// the search field or in Settings. The menu is never shown; only its key equivalents are used.
enum MainMenu {
    @MainActor
    static func install(openSettings: Selector, target: AnyObject) {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let app = NSMenu(title: "Swoop")
        let settings = NSMenuItem(title: "Settings…", action: openSettings, keyEquivalent: ",")
        settings.target = target
        app.addItem(settings)
        app.addItem(.separator())
        app.addItem(NSMenuItem(title: "Hide Swoop", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        app.addItem(NSMenuItem(title: "Quit Swoop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = app
        main.addItem(appItem)

        // Edit: nil-targeted actions go to the first responder (the focused text field).
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = edit
        main.addItem(editItem)

        // ⌘W closes Settings / onboarding windows.
        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowItem.submenu = window
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }
}
