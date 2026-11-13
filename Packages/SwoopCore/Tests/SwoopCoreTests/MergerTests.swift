import Testing
@testable import SwoopCore

@Suite("Window merger")
struct WindowMergerTests {
    typealias O = WindowObservation<Int>

    @Test func menuEntriesFillOnlyTheRemainder() {
        // Finder: one visible "Downloads" (ref 1) + three menu entries with that title → 1 visible + 2 menu-only.
        let merged = WindowMerger.merge([
            O(title: "Downloads", source: .visible, ref: 1),
            O(title: "Downloads", source: .menuOnly), O(title: "Downloads", source: .menuOnly), O(title: "Downloads", source: .menuOnly),
        ])
        #expect(merged.count == 3)
        #expect(merged.map(\.source) == [.visible, .menuOnly, .menuOnly])
        #expect(merged.allSatisfy { $0.titleMultiplicity == 3 })
    }

    @Test func sameElementFromSeveralSourcesIsDeduplicated() {
        let merged = WindowMerger.merge([
            O(title: "Doc", source: .mainOrFocused, ref: 7),
            O(title: "Doc", source: .visible, ref: 7),
            O(title: "Doc", source: .anchor, ref: 7),
            O(title: "Doc", source: .menuOnly),
        ])
        #expect(merged.count == 1)
        #expect(merged[0].source == .visible)
    }

    @Test func tabsAndVisibleWindowCoverMenuList() {
        // VS Code group: selected tab visible (ref 1), two hidden tabs, menu lists all three.
        let merged = WindowMerger.merge([
            O(title: "a — p1", source: .visible, ref: 1),
            O(title: "b — p2", source: .tab, ref: 1),
            O(title: "c — p3", source: .tab, ref: 1),
            O(title: "a — p1", source: .menuOnly), O(title: "b — p2", source: .menuOnly), O(title: "c — p3", source: .menuOnly),
            O(title: "d — p4", source: .menuOnly),
        ])
        #expect(merged.map(\.title) == ["a — p1", "b — p2", "c — p3", "d — p4"])
        #expect(merged.map(\.source) == [.visible, .tab, .tab, .menuOnly])
    }

    @Test func offSpaceMainWindowCountsAgainstMenu() {
        let merged = WindowMerger.merge([
            O(title: "Slack", source: .mainOrFocused, ref: 9),
            O(title: "Slack", source: .menuOnly),
        ])
        #expect(merged.count == 1 && merged[0].source == .mainOrFocused)
    }

    @Test func minimizedFlagFromMenu() {
        let merged = WindowMerger.merge([O(title: "Vault", source: .menuOnly, isMinimized: true)])
        #expect(merged[0].isMinimized)
    }

    @Test func truncatedAndDecoratedMenuTitlesClaimElements() {
        let merged = WindowMerger.merge([
            O(title: "repo: Heron API for clients without a dedicated API proxy. - Brave - Work", source: .mainOrFocused, ref: 1),
            O(title: "Activity Monitor – My Processes", source: .mainOrFocused, ref: 2),
            O(title: "repo: Heron A…without a dedicated API proxy.", source: .menuOnly),
            O(title: "Activity Monitor (My Processes)", source: .menuOnly),
        ])
        #expect(merged.count == 2)
        #expect(merged.allSatisfy { $0.source == .mainOrFocused })
    }

    @Test func menuTitleMatching() {
        #expect(WindowMerger.menuTitle("abc…xyz", matches: "abc 123 xyz - App"))
        #expect(!WindowMerger.menuTitle("abc…xyz", matches: "abd 123 xyz"))
        #expect(WindowMerger.menuTitle("A (B)", matches: "A – B"))
        #expect(!WindowMerger.menuTitle("Downloads", matches: "Documents"))
        #expect(!WindowMerger.menuTitle("—", matches: "–")) // punctuation-only titles never fuzzy-match
    }

    @Test func exactMatchesWinBeforeFuzzy() {
        // Exact "A – B" must claim the element titled "A – B", leaving "A (B)" menu entry for the other.
        let merged = WindowMerger.merge([
            O(title: "A – B", source: .visible, ref: 1),
            O(title: "A (B)", source: .visible, ref: 2),
            O(title: "A (B)", source: .menuOnly),
            O(title: "A – B", source: .menuOnly),
        ])
        #expect(merged.count == 2)
    }
}
