import AppKit
import os
import SwoopCore

/// Remembers window element ids per app *process* and finds new ones with low-priority background sweeps
/// (ARCHITECTURE §2a). Element ids live inside the target app and survive Swoop restarts, so the ids
/// are persisted: after a relaunch every previously known window is rebuilt directly, with no sweep.
///
/// Cost policy (PRD §14): nothing runs unless an app has windows Swoop can't reach otherwise; a sweep
/// covers each id at most once per app process (resumable cursor), runs in short slices with pauses on a
/// utility queue, and is capped (`RemoteRecoveryPolicy.sweepCap`).
final class RemoteWindowRecovery: Sendable {
    private struct AppState: Codable {
        var ids: Set<UInt64> = []
        var cursor: UInt64 = 0
        var swept: UInt64 = 0
        var sweeping = false
        enum CodingKeys: String, CodingKey { case ids, cursor } // swept/sweeping are per run
    }
    private struct State {
        var apps: [String: AppState] = [:]
        var saveScheduled = false
    }

    private static let defaultsKey = "remoteWindowIDs.v1"
    /// Work/pause slices: at most ~25% of one core per app being swept, at utility QoS, and only while a sweep
    /// is pending. Pauses are scheduled, not slept, so sweeps of different apps interleave on the serial queue.
    private static let sliceNanos: UInt64 = 8_000_000
    private static let pauseSeconds: TimeInterval = 0.024

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let queue = DispatchQueue(label: "com.bastienff.swoop.remote-sweep", qos: .utility)
    private let log = Logger(subsystem: "com.bastienff.swoop", category: "recovery")
    /// Called (on the sweep queue) when a sweep found new window elements for `pid`.
    private let onFound: @Sendable (pid_t) -> Void

    init(onFound: @escaping @Sendable (pid_t) -> Void) {
        self.onFound = onFound
        let alive = Set(NSWorkspace.shared.runningApplications.compactMap { Self.key(pid: $0.processIdentifier, launch: $0.launchDate) })
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([String: AppState].self, from: data) {
            state.withLock { $0.apps = saved.filter { alive.contains($0.key) } }
        }
    }

    /// Process identity that survives pid reuse. nil → not persisted/recovered (no launch date).
    static func key(pid: pid_t, launch: Date?) -> String? {
        launch.map { "\(pid)@\(Int($0.timeIntervalSince1970))" }
    }

    func knownIDs(_ key: String) -> Set<UInt64> { state.withLock { $0.apps[key]?.ids ?? [] } }

    func remember(_ key: String, _ ids: some Sequence<UInt64>) {
        let ids = Array(ids)
        guard !ids.isEmpty else { return }
        let changed = state.withLock { s in
            let before = s.apps[key]?.ids.count ?? 0
            s.apps[key, default: AppState()].ids.formUnion(ids)
            return s.apps[key]!.ids.count != before
        }
        if changed { scheduleSave() }
    }

    func forget(_ key: String, _ ids: [UInt64]) {
        guard !ids.isEmpty else { return }
        state.withLock { s in ids.forEach { s.apps[key]?.ids.remove($0) } }
        scheduleSave()
    }

    /// Forgets every remembered id and sweep cursor (debug: test recovery from scratch).
    func reset() {
        state.withLock { $0.apps = [:] }
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
    }

    /// Ids remembered and apps tracked (debug info).
    var stats: (apps: Int, ids: Int) {
        state.withLock { s in (s.apps.count, s.apps.values.reduce(0) { $0 + $1.ids.count }) }
    }

    /// Drops state of processes that are gone.
    func prune(keeping alive: Set<String>) {
        let removed = state.withLock { s in
            let before = s.apps.count
            s.apps = s.apps.filter { alive.contains($0.key) }
            return s.apps.count != before
        }
        if removed { scheduleSave() }
    }

    /// Starts a background sweep of ids not yet covered (up to `highWater` + margin), unless one is
    /// running or there is nothing new to cover. `knownWindows` are skipped (their wids are read on the
    /// sweep queue, only if a sweep actually starts).
    func requestSweep(key: String, pid: pid_t, highWater: UInt64, knownWindows: [AXElement]) {
        let start = state.withLock { s -> Bool in
            var a = s.apps[key, default: AppState()]
            guard !a.sweeping, RemoteRecoveryPolicy.nextSweepRange(cursor: a.cursor, highWater: highWater, swept: a.swept) != nil
            else { return false }
            a.sweeping = true
            s.apps[key] = a
            return true
        }
        guard start else { return }
        queue.async { [self] in
            let skip = Set(knownWindows.compactMap(RemoteElements.windowNumber))
            sweepSlice(SweepRun(key: key, pid: pid, highWater: highWater, skip: skip))
        }
    }

    /// Progress of one app's sweep, carried from slice to slice.
    private struct SweepRun: Sendable {
        let key: String
        let pid: pid_t
        let highWater: UInt64
        var skip: Set<CGWindowID>
        var found: [UInt64] = []
        var checked: UInt64 = 0
        let t0 = DispatchTime.now().uptimeNanoseconds
    }

    /// One work slice, then the next one is scheduled after a pause (the queue stays free in between, so
    /// other apps' sweeps and saves interleave instead of waiting).
    private func sweepSlice(_ run: SweepRun) {
        var run = run
        let (key, highWater) = (run.key, run.highWater)
        let range = state.withLock { s -> Range<UInt64>? in
            guard let a = s.apps[key] else { return nil }
            return RemoteRecoveryPolicy.nextSweepRange(cursor: a.cursor, highWater: highWater, swept: a.swept)
        }
        guard kill(run.pid, 0) == 0, let range else { finishSweep(run); return }
        let deadline = DispatchTime.now().uptimeNanoseconds + Self.sliceNanos
        let next = RemoteElements.sweepWindows(pid: run.pid, range: range, skipWindows: run.skip, deadline: deadline) { id, e in
            run.found.append(id)
            if let wid = RemoteElements.windowNumber(of: e) { run.skip.insert(wid) }
        }
        run.checked += next - range.lowerBound
        state.withLock { s in
            s.apps[key]?.cursor = next
            s.apps[key]?.swept += next - range.lowerBound
        }
        if next < range.upperBound {
            queue.asyncAfter(deadline: .now() + Self.pauseSeconds) { [self, run] in sweepSlice(run) }
        } else {
            queue.async { [self, run] in sweepSlice(run) } // range done: next range (or finish), no pause
        }
    }

    private func finishSweep(_ run: SweepRun) {
        let key = run.key
        state.withLock { $0.apps[key]?.sweeping = false }
        let ms = (DispatchTime.now().uptimeNanoseconds - run.t0) / 1_000_000
        log.info("sweep pid \(run.pid): \(run.checked) ids in \(ms) ms, \(run.found.count) windows")
        guard !run.found.isEmpty else { scheduleSave(); return }
        remember(run.key, run.found)
        onFound(run.pid)
    }

    private func scheduleSave() {
        let schedule = state.withLock { s -> Bool in
            if s.saveScheduled { return false }
            s.saveScheduled = true
            return true
        }
        guard schedule else { return }
        queue.asyncAfter(deadline: .now() + 3) { [self] in
            let snapshot = state.withLock { s -> [String: AppState] in
                s.saveScheduled = false
                return s.apps
            }
            if let data = try? JSONEncoder().encode(snapshot) {
                UserDefaults.standard.set(data, forKey: Self.defaultsKey)
            }
        }
    }
}
