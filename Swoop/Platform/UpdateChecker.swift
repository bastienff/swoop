import Foundation
import OSLog
import SwoopCore

/// The only network code in Swoop: asks GitHub for the latest release's version number, only with the
/// user's consent — when they click "Check for Updates", or once a day if they turned on automatic checks
/// (off by default). One anonymous GET; no cookies, no cache, nothing about the user or their windows.
/// It never downloads or installs anything: an update is shown as a link to its release page.
@MainActor
@Observable
final class UpdateChecker {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, page: URL)
        case failed(String)
    }

    private(set) var status: Status = .idle
    /// The newest release known to be an update (also remembered across launches), for the menu bar.
    var availableUpdate: (version: String, page: URL)? {
        if case .available(let v, let page) = status { return (v, page) }
        return nil
    }

    private let settings: AppSettings
    private let defaults: UserDefaults
    private var schedule: Task<Void, Never>?
    private let log = Logger(subsystem: "com.bastienff.swoop", category: "updates")

    private static let lastCheckKey = "lastUpdateCheck"
    private static let knownVersionKey = "latestKnownVersion"
    private static let latestReleaseAPI = URL(string: "https://api.github.com/repos/bastienff/swoop/releases/latest")!
    static let releasesPage = AppLinks.repository.appendingPathComponent("releases")

    /// This build's version, e.g. "1.1.0".
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    init(settings: AppSettings, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.defaults = defaults
        // An update found earlier stays visible after a relaunch until this build catches up.
        if let known = defaults.string(forKey: Self.knownVersionKey),
           UpdatePolicy.isUpdate(latest: known, current: Self.currentVersion) {
            status = .available(version: known, page: Self.releasePage(for: known))
        }
    }

    /// Starts or stops the daily automatic check to match the setting. No request is made while it's off.
    func applySetting() {
        schedule?.cancel()
        schedule = nil
        guard settings.checkForUpdates else { return }
        schedule = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10)) // not during launch
            while !Task.isCancelled {
                guard let self else { return }
                let last = defaults.object(forKey: Self.lastCheckKey) as? Date
                if UpdatePolicy.isDue(lastCheck: last, now: Date()) { await check() }
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    /// One request to GitHub. Called by the user ("Check for Updates") or the daily schedule.
    func check() async {
        guard status != .checking else { return }
        let previous = status
        status = .checking
        defer { if status == .checking { status = previous } }
        do {
            let latest = try await fetchLatestVersion()
            defaults.set(Date(), forKey: Self.lastCheckKey)
            if UpdatePolicy.isUpdate(latest: latest, current: Self.currentVersion) {
                let version = AppVersion(latest)?.description ?? latest
                defaults.set(version, forKey: Self.knownVersionKey)
                status = .available(version: version, page: Self.releasePage(for: version))
            } else {
                defaults.removeObject(forKey: Self.knownVersionKey)
                status = .upToDate
            }
            log.info("update check: latest \(latest, privacy: .public), running \(Self.currentVersion, privacy: .public)")
        } catch {
            log.error("update check failed: \(error.localizedDescription, privacy: .public)")
            status = .failed(Self.message(for: error))
        }
    }

    private struct Release: Decodable { let tag_name: String }
    private struct CheckError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private func fetchLatestVersion() async throws -> String {
        let config = URLSessionConfiguration.ephemeral // no cookies, no cache, no credentials
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = [
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "Swoop/\(Self.currentVersion)",
        ]
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        #if DEBUG
        if let mocked = try await debugMockedResponse() { return mocked }
        #endif
        let (data, response) = try await session.data(from: Self.latestReleaseAPI)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200: break
        case 403, 429: throw CheckError(message: String(localized: "GitHub is limiting requests right now. Try again later."))
        case 404: throw CheckError(message: String(localized: "No releases were found."))
        default: throw CheckError(message: String(localized: "GitHub answered with an error (\(code))."))
        }
        let tag = try JSONDecoder().decode(Release.self, from: data).tag_name
        guard AppVersion(tag) != nil else {
            throw CheckError(message: String(localized: "The latest release has an unexpected version (\(tag))."))
        }
        return tag
    }

    #if DEBUG
    /// Debug menu / Settings → Debug: answer checks with a canned response instead of asking GitHub (the
    /// repository may be private, or there may be no newer release to test with). Not compiled into Release.
    enum DebugMock: String, CaseIterable {
        case off, newVersion, upToDate, offline
        var label: String {
            switch self {
            case .off: "Real request (GitHub)"
            case .newVersion: "Mock: new version available"
            case .upToDate: "Mock: no new version"
            case .offline: "Mock: no connection"
            }
        }
    }

    private static let debugMockKey = "debugUpdateMock"

    var debugMock = DebugMock(rawValue: UserDefaults.standard.string(forKey: debugMockKey) ?? "") ?? .off {
        didSet { defaults.set(debugMock.rawValue, forKey: Self.debugMockKey); status = .idle }
    }

    /// Forgets the last check and any known update (as on a fresh install).
    func debugForget() {
        defaults.removeObject(forKey: Self.lastCheckKey)
        defaults.removeObject(forKey: Self.knownVersionKey)
        status = .idle
    }

    var debugSummary: String {
        let last = (defaults.object(forKey: Self.lastCheckKey) as? Date)?.formatted(date: .abbreviated, time: .shortened) ?? "never"
        let state: String = switch status {
        case .idle: "idle"
        case .checking: "checking"
        case .upToDate: "up to date"
        case .available(let v, _): "\(v) available"
        case .failed(let m): "failed: \(m)"
        }
        return "\(state) · last check \(last) · auto \(settings.checkForUpdates ? "on" : "off")"
    }

    /// The canned "latest release" tag for the current mock (after a short delay, so the spinner shows),
    /// nil for a real request.
    private func debugMockedResponse() async throws -> String? {
        let mock = debugMock
        guard mock != .off else { return nil }
        try await Task.sleep(for: .milliseconds(800))
        let current = AppVersion(Self.currentVersion)?.parts ?? [0]
        switch mock {
        case .off: return nil
        case .newVersion:
            let major = current.first ?? 0, minor = current.count > 1 ? current[1] : 0
            return "v\(major).\(minor + 1).0"
        case .upToDate: return "v\(Self.currentVersion)"
        case .offline: throw URLError(.notConnectedToInternet)
        }
    }
    #endif

    /// The release page is built from the version, never taken from the response, so a check can only
    /// ever open this repository's own Releases.
    private static func releasePage(for version: String) -> URL {
        releasesPage.appendingPathComponent("tag").appendingPathComponent("v\(version)")
    }

    private static func message(for error: Error) -> String {
        if let e = error as? CheckError { return e.message }
        if let e = error as? URLError {
            switch e.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return String(localized: "You're offline.")
            case .timedOut:
                return String(localized: "GitHub didn't answer in time.")
            default: break
            }
        }
        return error.localizedDescription
    }
}
