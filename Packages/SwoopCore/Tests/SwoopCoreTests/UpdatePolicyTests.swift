import Foundation
import Testing
@testable import SwoopCore

@Suite("Update policy")
struct UpdatePolicyTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func parsesTagsAndVersions() {
        #expect(AppVersion("v1.2.3")?.parts == [1, 2, 3])
        #expect(AppVersion("1.10")?.parts == [1, 10])
        #expect(AppVersion(" 2.0.0 ")?.parts == [2, 0, 0])
        #expect(AppVersion("1.3.0-beta") == nil)
        #expect(AppVersion("") == nil)
        #expect(AppVersion("1..2") == nil)
        #expect(AppVersion("latest") == nil)
    }

    @Test func comparesNumericallyPartByPart() {
        #expect(AppVersion("1.10.0")! > AppVersion("1.9.9")!)
        #expect(AppVersion("1.2")! == AppVersion("1.2.0")!)
        #expect(AppVersion("2.0")! > AppVersion("1.99.99")!)
        #expect(Set([AppVersion("1.2")!, AppVersion("1.2.0")!]).count == 1)
    }

    @Test func updateOnlyWhenStrictlyNewer() {
        #expect(UpdatePolicy.isUpdate(latest: "v1.1.0", current: "1.0.0"))
        #expect(!UpdatePolicy.isUpdate(latest: "v1.1.0", current: "1.1.0"))
        #expect(!UpdatePolicy.isUpdate(latest: "v1.0.0", current: "1.1.0"))
        #expect(!UpdatePolicy.isUpdate(latest: "v1.2.0-beta", current: "1.1.0"))
        #expect(!UpdatePolicy.isUpdate(latest: "v1.1.0", current: "?"))
    }

    @Test func automaticCheckAtMostDaily() {
        #expect(UpdatePolicy.isDue(lastCheck: nil, now: t0))
        #expect(!UpdatePolicy.isDue(lastCheck: t0, now: t0.addingTimeInterval(23 * 3600)))
        #expect(UpdatePolicy.isDue(lastCheck: t0, now: t0.addingTimeInterval(24 * 3600)))
        // Clock moved backwards: don't wait for it to catch up.
        #expect(UpdatePolicy.isDue(lastCheck: t0, now: t0.addingTimeInterval(-3600)))
    }
}
