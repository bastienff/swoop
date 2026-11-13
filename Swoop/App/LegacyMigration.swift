import Foundation

/// One-time import of data from the pre-rename app ("Switcher", bundle id `app.switcher.Switcher`):
/// preferences (incl. remembered window ids) and the recent-windows history. Runs before anything
/// reads settings. Accessibility and Launch at Login are tied to the bundle id and must be granted again.
enum LegacyMigration {
    private static let legacyBundleID = "app.switcher.Switcher"
    private static let doneKey = "migratedFromLegacySwitcher"

    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }

        if let old = defaults.persistentDomain(forName: legacyBundleID) {
            for (key, value) in old where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let oldDir = support.appendingPathComponent("Switcher", isDirectory: true)
        let newDir = support.appendingPathComponent("Swoop", isDirectory: true)
        if fm.fileExists(atPath: oldDir.path), !fm.fileExists(atPath: newDir.path) {
            try? fm.moveItem(at: oldDir, to: newDir)
        }
    }
}
