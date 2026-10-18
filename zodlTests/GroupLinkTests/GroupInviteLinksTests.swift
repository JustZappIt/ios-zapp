//
//  GroupInviteLinksTests.swift
//  zodlTests
//

import Foundation
import Testing
@testable import zodl_internal

/// Routing decisions only. What a link actually says is the SDK's to tell, and these never ask it.
@Suite struct GroupInviteLinksTests {
    private static let payload = "AQGLmx_sGDZTw7Gb8xx8Wp7a36GI8igPwlPzx-tpWRKD"
    private static let shared = "https://join.justzappit.xyz/g/v1#\(payload)"
    private static let handoff = "xyz.justzappit.zapp://g/v1/\(payload)"

    @Test func recognisesBothFormsAndNothingElse() {
        #expect(GroupInviteLinks.isGroupLink(Self.shared))
        #expect(GroupInviteLinks.isGroupLink(Self.handoff))

        #expect(!GroupInviteLinks.isGroupLink("https://gift.justzappit.xyz/c/v1#\(Self.payload)"))
        #expect(!GroupInviteLinks.isGroupLink("https://join.justzappit.xyz/other/v1#\(Self.payload)"))
        #expect(!GroupInviteLinks.isGroupLink("https://evil.example/g/v1#\(Self.payload)"))
        #expect(!GroupInviteLinks.isGroupLink("zcash:u1address"))
        #expect(!GroupInviteLinks.isGroupLink(""))
    }

    @Test func hostIsCaseInsensitiveAndTheQueryIsDropped() {
        let noisy = "https://JOIN.JustZappIt.xyz/g/v1?utm_source=whatsapp#\(Self.payload)"

        #expect(GroupInviteLinks.canonical(noisy) == Self.shared)
    }

    /// The fragment is the secret. Losing it would turn a good link into an unreadable one.
    @Test func keepsTheFragmentAndThePath() {
        #expect(GroupInviteLinks.canonical(Self.shared) == Self.shared)
        #expect(GroupInviteLinks.canonical(Self.handoff) == Self.handoff)
    }

    @Test func refusesSomethingTooLongToBeHonest() {
        let oversized = "https://join.justzappit.xyz/g/v1#" + String(repeating: "A", count: 2048)

        #expect(GroupInviteLinks.canonical(oversized) == nil)
    }

    @Test func findsALinkInsideAPastedSentence() {
        let pasted = "hey, join us here: \(Self.shared) — see you there"

        #expect(GroupInviteLinks.fromPastedText(pasted) == Self.shared)
        #expect(GroupInviteLinks.fromPastedText("(\(Self.shared))") == Self.shared)
        #expect(GroupInviteLinks.fromPastedText("nothing to see here") == nil)
    }
}
