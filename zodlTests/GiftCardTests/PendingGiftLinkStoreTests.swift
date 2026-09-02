// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
@testable import zodl_internal

@Suite struct PendingGiftLinkStoreTests {
    private static let maxPending = 16

    @Test func handsTheLinkBackForItsToken() throws {
        let store = PendingGiftLinkStore()
        let token = try accept(store, link("a"))

        #expect(store.take(token) == link("a"))
    }

    @Test func neverPutsTheLinkInTheToken() throws {
        let store = PendingGiftLinkStore()
        let secret = "mnemonic-words-that-are-the-money"

        let token = try accept(store, link(secret))

        #expect(!token.contains(secret), "the token must not carry any of the link")
    }

    @Test func coalescesARepeatedLink() {
        let store = PendingGiftLinkStore()
        _ = store.put(link("a"))

        // A link can arrive twice — a re-tapped chat message, a re-delivered deeplink. Opening a
        // second claim for one card would put two claim screens up for the same funds.
        #expect(store.put(link("a")) == .alreadyPending, "the same link must not open twice while it is waiting")
    }

    @Test func anActiveLinkCannotBeOpenedAgainUntilReleased() throws {
        let store = PendingGiftLinkStore()
        let token = try accept(store, link("a"))
        let raw = try #require(store.take(token))

        #expect(store.put(link("a")) == .alreadyPending)
        store.release(raw)
        guard case .accepted = store.put(link("a")) else {
            Issue.record("expected the store to accept the link after release")
            return
        }
    }

    @Test func takingTwiceYieldsNothingTheSecondTime() throws {
        let store = PendingGiftLinkStore()
        let token = try accept(store, link("a"))
        _ = store.take(token)

        #expect(store.take(token) == nil)
    }

    @Test func aTokenFromADeadProcessYieldsNothing() {
        // The token can outlive the store; the store does not resurrect.
        #expect(PendingGiftLinkStore().take("token-from-a-previous-process") == nil)
    }

    @Test func distinctLinksGetDistinctTokens() throws {
        let store = PendingGiftLinkStore()

        #expect(try accept(store, link("a")) != (try accept(store, link("b"))))
    }

    @Test func boundsTheStore() throws {
        let store = PendingGiftLinkStore()
        for index in 0..<Self.maxPending {
            _ = try accept(store, link("card\(index)"))
        }

        #expect(store.put(link("one-too-many")) == .refused, "the store must not grow without limit")
    }

    @Test func aFullStoreDrainsAsClaimsAreOpened() throws {
        let store = PendingGiftLinkStore()
        var tokens: [String] = []
        for index in 0..<Self.maxPending {
            tokens.append(try accept(store, link("card\(index)")))
        }

        _ = store.take(try #require(tokens.first))
        store.release(link("card0"))

        guard case .accepted = store.put(link("one-more")) else {
            Issue.record("taking a link must free its slot")
            return
        }
    }

    @Test func refusesALinkOverTheSizeBoundByCharacterCount() {
        let oversized = link(String(repeating: "a", count: GiftLinkCodec.maxURIBytes))

        #expect(PendingGiftLinkStore().put(oversized) == .refused)
    }

    @Test func refusesALinkWhoseBytesExceedTheBoundEvenThoughItsLengthDoesNot() {
        // Four bytes per character, so a string comfortably under the character bound is well over
        // the byte bound. Checking only the character count would let this through.
        let raw = link(String(repeating: "😀", count: GiftLinkCodec.maxURIBytes / 3))

        #expect(raw.count <= GiftLinkCodec.maxURIBytes, "precondition: under the character bound")
        #expect(raw.utf8.count > GiftLinkCodec.maxURIBytes, "precondition: over the byte bound")
        #expect(PendingGiftLinkStore().put(raw) == .refused)
    }

    @Test func handsADeferredLinkBackOnceAWalletExists() throws {
        let store = PendingGiftLinkStore()
        // The claim screen opened with no wallet behind it, spending the token on the way in.
        _ = store.take(try accept(store, link("a")))

        store.deferLink(link("a"))
        let resumed = try #require(store.resumeDeferred(), "a card left to go and make a wallet must come back")

        #expect(store.take(resumed) == link("a"))
    }

    @Test func resumesADeferredLinkOnlyOnce() {
        let store = PendingGiftLinkStore()
        store.deferLink(link("a"))
        _ = store.resumeDeferred()

        // The wallet-created signal fires once, but the effect that reads this can run again; a
        // second claim screen would be two attempts to spend the same note.
        #expect(store.resumeDeferred() == nil)
    }

    @Test func hasNothingToResumeWhenNoCardWasDeferred() {
        #expect(PendingGiftLinkStore().resumeDeferred() == nil)
    }

    /// A refusal here is a test that has already failed, so it says so rather than letting a later
    /// assertion report something unrelated.
    private func accept(_ store: PendingGiftLinkStore, _ raw: String) throws -> String {
        guard case .accepted(let token) = store.put(raw) else {
            throw TestRefusal(message: "expected the store to accept the link")
        }
        return token
    }

    private struct TestRefusal: Error {
        let message: String
    }

    private func link(_ body: String) -> String {
        "https://\(GiftLinkCodec.giftLinkHost)/c/v1#k=\(body)"
    }
}
