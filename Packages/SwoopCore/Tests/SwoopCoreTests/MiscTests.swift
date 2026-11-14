import Foundation
import Testing
@testable import SwoopCore

@Suite("VS Code titles")
struct VSCodeTitleTests {
    @Test(arguments: [
        ("heron.config.js — heron-api-proxy", "heron-api-proxy", "heron.config.js"),
        ("wren-cache", "wren-cache", nil),
        (".env — tern-notify", "tern-notify", ".env"),
        ("● main.ts — backend (Workspace)", "backend", "main.ts"),
        ("# Build a Native macOS Universal Window • Untitled-2 — finch-billing", "finch-billing", "# Build a Native macOS Universal Window • Untitled-2"),
        ("file-with-dash.ts — repo", "repo", "file-with-dash.ts"),
        ("a.ts — proj — Visual Studio Code", "proj", "a.ts"),
    ] as [(String, String, String?)])
    func parses(title: String, project: String, detail: String?) throws {
        let r = try #require(VSCodeTitleParser.parse(title))
        #expect(r.project == project)
        #expect(r.detail == detail)
    }

    @Test func rejectsEmptyAndAppOnly() {
        #expect(VSCodeTitleParser.parse("") == nil)
        #expect(VSCodeTitleParser.parse("Visual Studio Code") == nil)
    }

    @Test func bundleIDs() {
        #expect(VSCodeTitleParser.isVSCode("com.microsoft.VSCode"))
        #expect(VSCodeTitleParser.isVSCode("com.microsoft.VSCodeInsiders"))
        #expect(!VSCodeTitleParser.isVSCode("com.apple.finder"))
        #expect(!VSCodeTitleParser.isVSCode(nil))
    }
}

@Suite("Recent usage")
struct RecentUsageTests {
    @Test func recordsAndPrunesOldest() {
        var r = RecentUsage(capacity: 2)
        r.record("a", at: Date(timeIntervalSince1970: 1))
        r.record("b", at: Date(timeIntervalSince1970: 2))
        r.record("c", at: Date(timeIntervalSince1970: 3))
        #expect(r.date(for: "a") == nil)
        #expect(r.date(for: "c") != nil)
    }

    @Test func keyIgnoresLeadingStatusGlyphs() {
        #expect(RecentUsage.key(bundleID: "g", title: "◐ Build") == RecentUsage.key(bundleID: "g", title: "◑ Build"))
        #expect(RecentUsage.key(bundleID: "g", title: "● main.ts") == RecentUsage.key(bundleID: "g", title: "main.ts"))
        #expect(RecentUsage.key(bundleID: "g", title: "—") != RecentUsage.key(bundleID: "g", title: ""))
    }

    @Test func roundTripsThroughJSON() throws {
        var r = RecentUsage()
        r.record(RecentUsage.key(bundleID: "com.x", title: "t"), at: Date(timeIntervalSince1970: 100))
        let data = try JSONEncoder().encode(r)
        #expect(try JSONDecoder().decode(RecentUsage.self, from: data) == r)
    }
}

@Suite("Shortcut")
struct ShortcutTests {
    @Test func defaultIsOptionTab() {
        #expect(Shortcut.default.displayString == "⌥Tab")
        #expect(!Shortcut.default.isBareTab)
        #expect(Shortcut.default.knownConflict == nil)
    }

    @Test func conflicts() {
        #expect(Shortcut(keyCode: Shortcut.tabKeyCode, modifiers: [.command]).knownConflict != nil)
        #expect(Shortcut(keyCode: Shortcut.tabKeyCode, modifiers: []).isBareTab)
        #expect(Shortcut(keyCode: Shortcut.tabKeyCode, modifiers: []).knownConflict != nil)
    }

    @Test func holdModifiersIgnoreShiftUnlessAlone() {
        #expect(Shortcut.default.holdModifiers == [.option])
        #expect(Shortcut(keyCode: 0x30, modifiers: [.command, .shift]).holdModifiers == [.command])
        #expect(Shortcut(keyCode: 0x30, modifiers: [.shift]).holdModifiers == [.shift])
        #expect(Shortcut(keyCode: 0x30, modifiers: []).holdModifiers.isEmpty)
    }

    @Test func isHeld() {
        let s = Shortcut(keyCode: 0x30, modifiers: [.command, .option])
        #expect(s.isHeld(by: [.command, .option]))
        #expect(s.isHeld(by: [.command, .option, .shift]))
        #expect(!s.isHeld(by: [.command]))
        #expect(!s.isHeld(by: []))
        #expect(!Shortcut(keyCode: 0x30, modifiers: []).isHeld(by: []))
    }

    @Test func displayOrderFollowsMacConvention() {
        #expect(Shortcut(keyCode: 0x01, modifiers: [.command, .shift, .option, .control]).displayString == "⌃⌥⇧⌘S")
    }

    @Test func codable() throws {
        let s = Shortcut(keyCode: 0x31, modifiers: [.control, .option])
        #expect(try JSONDecoder().decode(Shortcut.self, from: JSONEncoder().encode(s)) == s)
    }
}

@Suite("Refresh scheduler")
struct RefreshSchedulerTests {
    let t0 = Date(timeIntervalSince1970: 1000)
    let title = RefreshScheduler<Int>.Policy(quiet: 1, maxWait: 3)
    let ratedTitle = RefreshScheduler<Int>.Policy(quiet: 0.5, maxWait: 3, minInterval: 3)
    let structure = RefreshScheduler<Int>.Policy(quiet: 0.3, maxWait: 1)

    @Test func singleEventWaitsForQuiet() {
        var s = RefreshScheduler<Int>()
        #expect(abs(s.event(1, policy: title, now: t0) - 1) < 1e-6)
    }

    @Test func continuousEventsAreCappedByMaxWait() {
        // A spinner changing the title every 100 ms still refreshes 3 s after the first change.
        var s = RefreshScheduler<Int>()
        var delay = 0.0
        for i in 0..<25 { delay = s.event(1, policy: title, now: t0.addingTimeInterval(Double(i) * 0.1)) }
        #expect(abs(delay - 0.6) < 1e-6) // fired at t0 + 3.0 (last event at t0 + 2.4)
    }

    @Test func structuralEventTightensTheBatch() {
        var s = RefreshScheduler<Int>()
        _ = s.event(1, policy: title, now: t0)
        #expect(abs(s.event(1, policy: structure, now: t0.addingTimeInterval(0.5)) - 0.3) < 1e-6)
        // A later title event in the same batch can't push it past the structural cap (t0 + 1).
        #expect(abs(s.event(1, policy: title, now: t0.addingTimeInterval(0.8)) - 0.2) < 1e-6)
    }

    @Test func sparseEventsAreRateLimitedByMinInterval() {
        // One title change per second (a slow spinner): each would go quiet, but refreshes stay 3 s apart.
        var s = RefreshScheduler<Int>()
        #expect(abs(s.event(1, policy: ratedTitle, now: t0) - 0.5) < 1e-6) // first refresh: just the quiet period
        s.fired(1, now: t0.addingTimeInterval(0.5))
        #expect(abs(s.event(1, policy: ratedTitle, now: t0.addingTimeInterval(1)) - 2.5) < 1e-6) // not before t0 + 3.5
        // A structural change in the same batch isn't held back by the title rate limit.
        #expect(abs(s.event(1, policy: structure, now: t0.addingTimeInterval(1.5)) - 0.3) < 1e-6)
    }

    @Test func firingStartsANewBatchAndKeysAreIndependent() {
        var s = RefreshScheduler<Int>()
        _ = s.event(1, policy: title, now: t0)
        s.fired(1, now: t0)
        #expect(abs(s.event(1, policy: title, now: t0.addingTimeInterval(10)) - 1) < 1e-6)
        #expect(abs(s.event(2, policy: structure, now: t0.addingTimeInterval(10)) - 0.3) < 1e-6)
    }
}

@Suite("Focus steal policy")
struct FocusStealPolicyTests {
    func decide(_ bundle: String? = "com.example.app", own: Bool = false, held: Shortcut.Modifiers = [],
                ownHold: Shortcut.Modifiers = [], click: TimeInterval? = nil, modifier: TimeInterval? = nil,
                reclaims: Int = 0) -> FocusStealPolicy.Decision {
        FocusStealPolicy.decide(newFrontmostBundleID: bundle, isOwnApp: own, heldModifiers: held, ownHoldModifiers: ownHold,
                                secondsSinceOutsideClick: click, secondsSinceModifier: modifier, reclaimsSoFar: reclaims)
    }

    @Test func appTakingFocusOnItsOwnIsReclaimed() {
        #expect(decide() == .reclaim)
        #expect(decide(click: 5) == .reclaim)        // an old click doesn't count
        #expect(decide(held: [.shift]) == .reclaim)  // Shift alone isn't a shortcut
    }

    @Test func userActionsAreRespected() {
        #expect(decide(held: [.command]) == .respect)          // ⌘Tab, ⌘Space
        #expect(decide(held: [.option]) == .respect)           // e.g. a launcher on ⌥Space
        #expect(decide(click: 0.1) == .respect)                // clicked outside
        #expect(decide(own: true) == .respect)                 // Swoop's own Settings window
        #expect(decide(nil) == .respect)                       // unknown: don't guess
        #expect(decide(modifier: 0.3) == .respect)             // ⌘Tab: ⌘ released just before the switch
    }

    @Test func appWithoutBundleIDAndOldModifiersAreReclaimed() {
        #expect(decide("") == .reclaim)
        #expect(decide(modifier: 3) == .reclaim)
    }

    @Test func modifierHeldForSwitchOnReleaseIsNotAShortcut() {
        #expect(decide(held: [.option], ownHold: [.option]) == .reclaim)
        #expect(decide(held: [.option, .command], ownHold: [.option]) == .respect)
    }

    @Test func systemUIIsNeverFought() {
        for id in ["com.apple.SecurityAgent", "com.apple.Spotlight", "com.apple.loginwindow", "com.apple.dock"] {
            #expect(decide(id) == .respect)
        }
    }

    @Test func givesUpAfterTheLimit() {
        #expect(decide(reclaims: FocusStealPolicy.maxReclaims - 1) == .reclaim)
        #expect(decide(reclaims: FocusStealPolicy.maxReclaims) == .respect)
    }
}
