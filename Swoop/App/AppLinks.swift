import Foundation

/// Public links shown in the app (menu bar, About) and the README.
enum AppLinks {
    static let sponsor = URL(string: "https://github.com/sponsors/bastienff")!
    static let repository = URL(string: "https://github.com/bastienff/swoop")!

    /// The repository's issue forms (`.github/ISSUE_TEMPLATE`). Field ids must match the form's `id`s.
    enum IssueTemplate: String {
        case bugReport = "bug_report.yml"
        case featureRequest = "feature_request.yml"
    }

    /// A "new issue" page with the form pre-filled. Nothing is sent until the user submits it on GitHub.
    /// Only non-identifying details go in the URL — never window titles or diagnostics.
    static func newIssue(_ template: IssueTemplate, fields: [String: String] = [:]) -> URL {
        var components = URLComponents(url: repository.appendingPathComponent("issues/new"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "template", value: template.rawValue)]
            + fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String
        return build.map { $0 == version ? version : "\(version) (\($0))" } ?? version
    }

    /// e.g. "macOS 27.2.0, Mac15,3".
    static var systemDescription: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let modelName = String(cString: model)
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)" + (modelName.isEmpty ? "" : ", \(modelName)")
    }
}
