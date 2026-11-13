import Foundation

/// Parses VS Code window titles (default `window.title`: `${dirty}${activeEditorShort}${separator}${rootName}`).
public enum VSCodeTitleParser {
    public static let bundleIDs: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.vscodium",
        "com.visualstudio.code.oss",
    ]

    public static func isVSCode(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleIDs.contains(bundleID)
    }

    /// Separator used by VS Code's default title (" — ", em dash). " - " is accepted as a fallback
    /// only when the em dash is absent, because file names commonly contain hyphens.
    public static func parse(_ rawTitle: String) -> (project: String, detail: String?)? {
        var title = rawTitle.trimmingCharacters(in: .whitespaces)
        for prefix in ["● ", "• "] where title.hasPrefix(prefix) { title.removeFirst(prefix.count) }
        guard !title.isEmpty else { return nil }
        let parts = title.components(separatedBy: " — ")
        var project = parts.last!.trimmingCharacters(in: .whitespaces)
        var detail: String? = parts.count > 1 ? parts.dropLast().joined(separator: " — ") : nil
        // Remote / dev-host decorations.
        for suffix in [" (Workspace)", " [Extension Development Host]", " [Administrator]"] where project.hasSuffix(suffix) {
            project.removeLast(suffix.count)
        }
        if project.hasPrefix("[Extension Development Host] ") { project.removeFirst("[Extension Development Host] ".count) }
        if parts.count > 2, project == "Visual Studio Code" || project == "Code" {
            // Custom title ending with the app name: project is the previous component.
            project = parts[parts.count - 2]
            detail = parts.count > 2 ? parts.dropLast(2).joined(separator: " — ") : nil
        }
        project = project.trimmingCharacters(in: .whitespaces)
        if project.isEmpty || project == "Visual Studio Code" { return nil }
        if let d = detail, d.isEmpty { detail = nil }
        return (project, detail)
    }
}
