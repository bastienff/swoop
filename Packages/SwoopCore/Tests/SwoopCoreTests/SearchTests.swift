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
        // Letters spelled out as separate words are initials now, but never outrank the real word.
        let spelled = [makeEntry("Notes", "h e r o n long scattered text"), makeEntry("Code", "heron-api-proxy")]
        #expect(WindowSearchEngine.rank(spelled, query: "heron").first?.appName == "Code")
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

    @Test func smartOrderPutsPreviousWindowFirst() {
        // You're in B (frontmost, most recent); the window you came from (D) leads.
        var entries = [makeEntry("A", "a", used: 10), makeEntry("B", "b", used: 30), makeEntry("C", "c"), makeEntry("D", "d", used: 20)]
        entries[1].pid = 42
        let smart = WindowSearchEngine.Options(order: .smart, frontmostPID: 42)
        #expect(WindowSearchEngine.rank(entries, query: "", options: smart).map(\.appName) == ["D", "B", "A", "C"])
    }

    @Test func smartOrderKeepsRecencyWhenFrontmostAppIsNotFirst() {
        // Frontmost app has no window at the top (e.g. Finder with only the desktop): nothing is demoted.
        let entries = [makeEntry("A", "a", used: 10), makeEntry("B", "b", used: 30)]
        let smart = WindowSearchEngine.Options(order: .smart, frontmostPID: 999)
        #expect(WindowSearchEngine.rank(entries, query: "", options: smart).map(\.appName) == ["B", "A"])
        #expect(WindowSearchEngine.rank(Array(entries.prefix(1)), query: "", options: smart).map(\.appName) == ["A"])
    }

    @Test func nameOrderIsAlphabeticalByAppThenTitle() {
        let entries = [makeEntry("slack", "general", used: 50), makeEntry("Code", "zeta"), makeEntry("Code", "Alpha", used: 1)]
        let byName = WindowSearchEngine.Options(order: .name)
        #expect(WindowSearchEngine.rank(entries, query: "", options: byName).map(\.title) == ["Alpha", "zeta", "general"])
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

@Suite("Initials matching")
struct InitialsTests {
    private func initials(_ text: String) -> String { String(WindowSearchEngine.wordStarts(text).map(\.char)) }

    @Test func wordStartsSplitOnSeparatorsAndCamelCase() {
        #expect(initials("Visual Studio Code") == "vsc")
        #expect(initials("heron-web") == "hw")
        #expect(initials("HeronWeb") == "hw")
        #expect(initials("VSCode") == "vc")
        #expect(initials("iTerm2") == "it2")
        #expect(initials("Code — heron.config.js") == "chcj")
        #expect(initials("Éditeur Rapide") == "er") // normalized
    }

    @Test func initialsTierSitsBetweenWordPrefixAndSubstring() throws {
        let wordPrefix = try #require(WindowSearchEngine.score(query: "vsc", in: "my vsc notes"))
        let all = try #require(WindowSearchEngine.score(query: "vsc", in: "Visual Studio Code"))
        let leading = try #require(WindowSearchEngine.score(query: "vs", in: "Visual Studio Code"))
        let run = try #require(WindowSearchEngine.score(query: "sc", in: "Visual Studio Code"))
        let substring = try #require(WindowSearchEngine.score(query: "hw", in: "touchwood"))
        let gapped = try #require(WindowSearchEngine.score(query: "vc", in: "Visual Studio Code"))
        #expect(wordPrefix > all)
        #expect(all > leading)       // covering every initial beats covering some
        #expect(leading > run)       // the start of the name beats a run further in
        #expect(run > substring)
        #expect(substring > gapped)  // initials with gaps stay a weak fuzzy match
    }

    @Test func initialsBeatAccidentalMidWordMatches() {
        let entries = [
            makeEntry("Terminal", "~/notes — touchwood"),
            makeEntry("Safari", "heron-web — Overview"),
        ]
        #expect(WindowSearchEngine.rank(entries, query: "hw").first?.appName == "Safari")
    }

    @Test func appNameInitials() {
        let entries = [
            makeEntry("Finder", "Downloads"),
            makeEntry("Visual Studio Code", "main.swift"),
            makeEntry("Slack", "#vsc-team-chat"), // word prefix: a real word still wins
        ]
        #expect(WindowSearchEngine.rank(entries, query: "vsc").map(\.appName) == ["Slack", "Visual Studio Code"])
    }

    @Test func camelCaseTitleInitials() {
        let entries = [makeEntry("Xcode", "Sandwich.swift"), makeEntry("Xcode", "HeronWeb.swift")]
        #expect(WindowSearchEngine.rank(entries, query: "hw").first?.title == "HeronWeb.swift")
    }

    @Test func projectBoostStaysBelowAFullInitialsMatch() {
        // A VS Code project that merely contains the query mid-word must not beat a name it fully abbreviates.
        let entries = [
            makeEntry("Code", "x — touchwood", bundle: "com.microsoft.VSCode"),
            makeEntry("Safari", "Heron Web"),
        ]
        #expect(WindowSearchEngine.rank(entries, query: "hw").first?.appName == "Safari")
    }

    @Test func matchRangesEmphasizeInitialsOrSubstring() {
        func marked(_ q: String, _ text: String) -> String {
            WindowSearchEngine.matchRanges(query: q, in: text).map { String(text[$0]) }.joined(separator: "|")
        }
        #expect(marked("vsc", "Visual Studio Code") == "V|S|C")
        #expect(marked("hw", "HeronWeb.swift") == "H|W")
        #expect(marked("vc", "Visual Studio Code") == "V|C")
        #expect(marked("studio", "Visual Studio Code") == "Studio")
        #expect(marked("tud", "Visual Studio Code") == "tud")
        #expect(marked("xyz", "Visual Studio Code") == "")
        #expect(marked("hron", "heron") == "") // other fuzzy matches aren't emphasized
    }
}
