import Testing
@testable import SwoopCore

@Suite("Remote recovery policy")
struct RemoteRecoveryTests {
    typealias P = RemoteRecoveryPolicy

    @Test func groupVisibleWindowIsAnchor() {
        #expect(P.classify(title: "a — p", selectedTabTitle: .some("a — p"), knownHiddenTabTitles: [],
                           windowsSharingFrame: 16, accountedSharingFrame: 0) == .anchor)
    }

    @Test func elementWithTabBarShowingAnotherTabIsHidden() {
        #expect(P.classify(title: "a", selectedTabTitle: .some("b"), knownHiddenTabTitles: [],
                           windowsSharingFrame: 2, accountedSharingFrame: 0) == .hiddenTab)
    }

    @Test func knownHiddenTabTitleIsHidden() {
        // Real case: VS Code "wren-cache" recovered by id, no tab bar, listed as value=0 in the main group.
        #expect(P.classify(title: "wren-cache", selectedTabTitle: nil, knownHiddenTabTitles: ["wren-cache"],
                           windowsSharingFrame: 16, accountedSharingFrame: 16) == .hiddenTab)
    }

    @Test func maximizedStandaloneIsAnchorWhenOthersAccounted() {
        // 16-tab group (known) + this standalone window, all maximized → 17 share the frame.
        #expect(P.classify(title: "x", selectedTabTitle: nil, knownHiddenTabTitles: [],
                           windowsSharingFrame: 17, accountedSharingFrame: 16) == .anchor)
    }

    @Test func unexplainedSharedFrameIsAmbiguous() {
        #expect(P.classify(title: "x", selectedTabTitle: nil, knownHiddenTabTitles: [],
                           windowsSharingFrame: 3, accountedSharingFrame: 1) == .ambiguous)
    }

    @Test func uniqueFrameIsAnchor() {
        #expect(P.classify(title: "x", selectedTabTitle: nil, knownHiddenTabTitles: [],
                           windowsSharingFrame: 1, accountedSharingFrame: 0) == .anchor)
    }

    @Test func sweepRangeCoversHighWaterPlusMargin() {
        #expect(P.nextSweepRange(cursor: 0, highWater: 136, swept: 0) == 0..<648)
    }

    @Test func sweepResumesFromCursor() {
        #expect(P.nextSweepRange(cursor: 648, highWater: 136, swept: 648) == nil)
        #expect(P.nextSweepRange(cursor: 648, highWater: 900, swept: 648) == 648..<1412)
    }

    @Test func sweepRespectsCap() {
        #expect(P.nextSweepRange(cursor: 0, highWater: 10_000_000, swept: 0, cap: 1000) == 0..<1000)
        #expect(P.nextSweepRange(cursor: 1000, highWater: 10_000_000, swept: 1000, cap: 1000) == nil)
    }
}
