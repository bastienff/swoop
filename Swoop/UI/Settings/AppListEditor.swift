import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SwoopCore

/// Rows for one of the app lists in Settings (hidden apps, apps that ignore the shortcut): each app with
/// its icon and a remove button, then an "Add App" menu of running apps plus "Choose App…".
struct AppListEditor: View {
    @Binding var list: AppList

    var body: some View {
        if list.isEmpty {
            Text("No apps").foregroundStyle(.secondary)
        }
        ForEach(list.apps) { app in
            HStack(spacing: 8) {
                Image(nsImage: Self.icon(for: app.bundleID))
                    .resizable().frame(width: 20, height: 20)
                Text(app.name)
                Spacer()
                Button {
                    list.remove(app.bundleID)
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove \(app.name)")
                .accessibilityLabel(Text("Remove \(app.name)"))
            }
        }
        Menu("Add App") {
            let running = Self.runningApps.filter { !list.contains($0.bundleID) }
            ForEach(running) { app in
                Button {
                    list.add(app)
                } label: {
                    Label { Text(app.name) } icon: { Image(nsImage: Self.icon(for: app.bundleID, size: 16)) }
                }
            }
            if !running.isEmpty { Divider() }
            Button("Choose App…") { if let app = Self.chooseApp() { list.add(app) } }
        }
        .fixedSize()
    }

    /// Apps with a Dock presence that are running now, Swoop excluded, by name.
    private static var runningApps: [AppList.App] {
        let own = Bundle.main.bundleIdentifier
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> AppList.App? in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier, id != own else { return nil }
            return AppList.App(bundleID: id, name: app.localizedName ?? id)
        }
        return AppList(apps).apps
    }

    private static func chooseApp() -> AppList.App? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Add")
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url),
              let id = bundle.bundleIdentifier else { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        return AppList.App(bundleID: id, name: name)
    }

    private static func icon(for bundleID: String, size: CGFloat = 20) -> NSImage {
        let image = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        image.size = NSSize(width: size, height: size)
        return image
    }
}

/// The switcher's context-menu item that hides the clicked window's app.
struct HideAppMenuItem: View {
    let entry: WindowEntry
    let model: SearchViewModel

    var body: some View {
        Button("Hide \(entry.appName) from Swoop") { model.onHideApp?(entry) }
            .disabled(entry.bundleID == nil)
    }
}
