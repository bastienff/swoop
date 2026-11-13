import Foundation
import Testing
@testable import SwoopCore

private func makeEntry(_ app: String, _ title: String, bundle: String? = nil, used: TimeInterval? = nil, id: String? = nil) -> WindowEntry {
    var e = WindowEntry(id: id ?? "\(app)|\(title)", pid: 1, bundleID: bundle, appName: app, title: title, source: .visible,
                        lastUsed: used.map { Date(timeIntervalSince1970: $0) })
    if VSCodeTitleParser.isVSCode(bundle), let p = VSCodeTitleParser.parse(title) {
        e.projectName = p.project; e.detail = p.detail
    }
    return e
}

@Suite("Search scoring")
struct SearchScoringTests {
    @Test func tiersAreOrdered() throws {
        let exact = try #require(WindowSearchEngine.score(query: "slack", in: "Slack"))
        let prefix = try #require(WindowSearchEngine.score(query: "sla", in: "Slack"))
        let word = try #require(WindowSearchEngine.score(query: "proxy", in: "heron-api proxy"))
        let substring = try #require(WindowSearchEngine.score(query: "eron", in: "heron"))
        let fuzzy = try #require(WindowSearchEngine.score(query: "hrn", in: "heron"))
        #expect(exact > prefix)
        #expect(prefix > word)
        #expect(word > substring)
        #expect(substring > fuzzy)
    }

    @Test func caseAndDiacriticInsensitive() {
        #expect(WindowSearchEngine.score(query: "NOTES", in: "notes") == 1000)
        #expect(WindowSearchEngine.score(query: "configuracion", in: "Configuración del Sistema") != nil)
    }

    @Test func rejectsNonMatchesAndScatteredFuzzy() {
        #expect(WindowSearchEngine.score(query: "xyz", in: "Slack") == nil)
        #expect(WindowSearchEngine.score(query: "heron", in: "h e r o n long scattered text") == nil
                || WindowSearchEngine.score(query: "heron", in: "h e r o n long scattered text")! < 500)
        #expect(WindowSearchEngine.score(query: "zqx", in: "zebra quick xylophone") != nil) // word boundaries ok
    }

    @Test func scatteredSubsequenceIsRejected() {
        // Real case: "heron" must not match "Native macOS Universal Window" (n-a-t…u…r…a).
        #expect(WindowSearchEngine.score(query: "heron", in: "# Build a Native macOS Universal Window • Untitled-2 — finch-billing") == nil)
        #expect(WindowSearchEngine.score(query: "hap", in: "heron-api-proxy") != nil)   // acronym
        #expect(WindowSearchEngine.score(query: "hron", in: "heron") != nil)            // compact fuzzy
    }

    @Test func emptyQueryMatchesNothingDirectly() {
        #expect(WindowSearchEngine.score(query: "  ", in: "Slack") == nil)
    }
}

@Suite("Search ranking")
struct SearchRankingTests {
    @Test func referenceImageHeronFilter() {
        // Image 1: typing "heron" leaves Postman and the VS Code heron window.
        let entries = [
            makeEntry("Slack", "monitoring (Channel) - Larkspur"),
            makeEntry("Postman", "https://finch-billing.heron.local/orders"),
            makeEntry("Code", ".env — heron-api-proxy", bundle: "com.microsoft.VSCode"),
            makeEntry("Code", "wren-cache", bundle: "com.microsoft.VSCode"),
            makeEntry("Notes", "Notes – 42 notes"),
        ]
        let r = WindowSearchEngine.rank(entries, query: "heron")
        #expect(r.map(\.appName) == ["Code", "Postman"])
    }

    @Test func emptyQueryIsMostRecentlyUsedFirst() {
        let entries = [makeEntry("A", "a", used: 10), makeEntry("B", "b", used: 30), makeEntry("C", "c"), makeEntry("D", "d", used: 20)]
        #expect(WindowSearchEngine.rank(entries, query: "").map(\.appName) == ["B", "D", "A", "C"])
    }

    @Test func recencyBreaksTies() {
        let entries = [makeEntry("Code", "alpha", used: 5, id: "1"), makeEntry("Code", "alpha", used: 50, id: "2")]
        #expect(WindowSearchEngine.rank(entries, query: "alpha").map(\.id) == ["2", "1"])
    }

    @Test func vscodeBoostDoesNotBeatBetterTier() {
        // Exact app-name match for Slack must beat a VS Code project that merely contains the query.
        let entries = [
            makeEntry("Code", "x — myslackbot", bundle: "com.microsoft.VSCode"),
            makeEntry("Slack", "general"),
        ]
        #expect(WindowSearchEngine.rank(entries, query: "slack").first?.appName == "Slack")
    }

    @Test func vscodeBoostBreaksSameTier() {
        let entries = [
            makeEntry("Terminal", "backend logs"),
            makeEntry("Code", "main.ts — backend", bundle: "com.microsoft.VSCode"),
        ]
        #expect(WindowSearchEngine.rank(entries, query: "backend").first?.appName == "Code")
    }

    @Test func multiWordQuery() {
        let entries = [makeEntry("Code", "heron.config.js — heron-api-proxy", bundle: "com.microsoft.VSCode"),
                       makeEntry("Code", "wren-cache", bundle: "com.microsoft.VSCode")]
        #expect(WindowSearchEngine.rank(entries, query: "code heron").map(\.title) == ["heron.config.js — heron-api-proxy"])
    }
}
