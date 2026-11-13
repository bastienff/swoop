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
