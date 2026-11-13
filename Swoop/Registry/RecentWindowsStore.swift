import Foundation
import SwoopCore

/// Persists MRU timestamps locally (Application Support/Swoop/recents.json). Never leaves the machine.
@MainActor
final class RecentWindowsStore {
    private(set) var usage: RecentUsage
    private let url: URL
    private var saveTask: Task<Void, Never>?

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Swoop", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("recents.json")
        usage = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(RecentUsage.self, from: $0) } ?? RecentUsage()
    }

    func record(_ key: String, at date: Date = Date()) {
        usage.record(key, at: date)
        scheduleSave()
    }

    func date(for key: String) -> Date? { usage.date(for: key) }

    func reset() {
        usage.reset()
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.flush()
        }
    }

    func flush() {
        guard let data = try? JSONEncoder().encode(usage) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
