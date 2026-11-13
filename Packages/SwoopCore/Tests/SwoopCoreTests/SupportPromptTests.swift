import Foundation
import Testing
@testable import SwoopCore

@Suite("Support prompt policy")
struct SupportPromptTests {
    typealias P = SupportPromptPolicy
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 24 * 3600

    @Test func firstCardAfterTwoDaysOfUse() {
        let s = SupportPromptState(firstSeen: t0, switches: 50)
        #expect(!P.isDue(s, now: t0.addingTimeInterval(1.9 * day)))
        #expect(P.isDue(s, now: t0.addingTimeInterval(2 * day)))
    }

    @Test func firstCardRightAwayAtHundredSwitches() {
        let s = SupportPromptState(firstSeen: t0, switches: 100)
        #expect(P.isDue(s, now: t0.addingTimeInterval(3600)))
        #expect(!P.isDue(SupportPromptState(firstSeen: t0, switches: 99), now: t0.addingTimeInterval(3600)))
    }

    @Test func timePathNeedsSomeUsage() {
        let s = SupportPromptState(firstSeen: t0, switches: P.minimumSwitches - 1)
        #expect(!P.isDue(s, now: t0.addingTimeInterval(30 * day)))
    }

    @Test func hundredTriggerOnlyFirstTime() {
        // Shown once at 100 switches, "Maybe later": many more switches don't bring it back early.
        let now = t0.addingTimeInterval(3600)
        var s = P.resolve(SupportPromptState(firstSeen: t0, switches: 100), .later, now: now)
        s.switches = 500
        #expect(!P.isDue(s, now: now.addingTimeInterval(1.9 * day)))
        #expect(P.isDue(s, now: now.addingTimeInterval(2 * day)))
    }

    @Test func laterAsksAgainInTwoDays() {
        let now = t0.addingTimeInterval(3 * day)
        let s = P.resolve(SupportPromptState(firstSeen: t0, switches: 20), .later, now: now)
        #expect(!P.isDue(s, now: now.addingTimeInterval(1.9 * day)))
        #expect(P.isDue(s, now: now.addingTimeInterval(2 * day)))
        #expect(s.timesShown == 1)
    }

    @Test func supportedOrNeverStopsForGood() {
        let now = t0.addingTimeInterval(3 * day)
        for outcome in [P.Outcome.supported, .never] {
            var s = P.resolve(SupportPromptState(firstSeen: t0, switches: 200), outcome, now: now)
            s.switches = 1000
            #expect(s.optedOut)
            #expect(!P.isDue(s, now: now.addingTimeInterval(400 * day)))
        }
    }
}
