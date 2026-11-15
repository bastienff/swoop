import Foundation
import Testing
@testable import SwoopCore

@Suite("App lists")
struct AppListTests {
    private let chrome = AppList.App(bundleID: "com.google.Chrome", name: "Google Chrome")
    private let parallels = AppList.App(bundleID: "com.parallels.desktop.console", name: "Parallels Desktop")
    private let arc = AppList.App(bundleID: "company.thebrowser.Browser", name: "Arc")

    @Test func matchesBundleIDsCaseInsensitively() {
        let list = AppList([chrome])
        #expect(list.contains("com.google.Chrome"))
        #expect(list.contains("COM.GOOGLE.CHROME"))
        #expect(!list.contains("com.google.Chrome.canary"))
        #expect(!list.contains(nil))
        #expect(!list.contains(""))
    }

    @Test func staysSortedByNameWithoutDuplicates() {
        var list = AppList([parallels, chrome])
        list.add(arc)
        list.add(AppList.App(bundleID: "COM.google.chrome", name: "Chrome"))  // same app, new name
        #expect(list.apps.map(\.name) == ["Arc", "Chrome", "Parallels Desktop"])
    }

    @Test func ignoresAppsWithoutBundleID() {
        var list = AppList()
        list.add(AppList.App(bundleID: "", name: "Mystery"))
        #expect(list.isEmpty)
    }

    @Test func removes() {
        var list = AppList([chrome, arc])
        list.remove("com.GOOGLE.chrome")
        #expect(list.apps == [arc])
    }

    @Test func roundTripsAsAPlainArray() throws {
        let list = AppList([parallels, chrome])
        let data = try JSONEncoder().encode(list)
        #expect(try JSONDecoder().decode([AppList.App].self, from: data).count == 2)
        #expect(try JSONDecoder().decode(AppList.self, from: data) == list)
        // Stored data from elsewhere is cleaned up on load.
        let messy = try JSONEncoder().encode([parallels, chrome, chrome])
        #expect(try JSONDecoder().decode(AppList.self, from: messy).apps.map(\.name) == ["Google Chrome", "Parallels Desktop"])
    }

    @Test func shortcutIsSuspendedOnlyForListedFrontApps() {
        let ignored = AppList([parallels])
        let own = "com.bastienff.swoop"
        #expect(ShortcutSuspension.shouldSuspend(frontmostBundleID: "com.parallels.desktop.console", ownBundleID: own, ignored: ignored))
        #expect(!ShortcutSuspension.shouldSuspend(frontmostBundleID: "com.google.Chrome", ownBundleID: own, ignored: ignored))
        #expect(!ShortcutSuspension.shouldSuspend(frontmostBundleID: nil, ownBundleID: own, ignored: ignored))
        // Swoop itself never suspends its shortcut, even if someone lists it.
        #expect(!ShortcutSuspension.shouldSuspend(frontmostBundleID: own, ownBundleID: own,
                                                  ignored: AppList([AppList.App(bundleID: own, name: "Swoop")])))
    }
}
