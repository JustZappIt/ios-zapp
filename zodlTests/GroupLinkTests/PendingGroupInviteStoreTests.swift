//
//  PendingGroupInviteStoreTests.swift
//  zodlTests
//

import Foundation
import Testing
@testable import zodl_internal

/// The store holds a bearer secret, so what it forgets matters as much as what it keeps.
@Suite struct PendingGroupInviteStoreTests {
    private static func link(_ suffix: String) -> String {
        "https://join.justzappit.xyz/g/v1#AQGLmx_sGDZTw7Gb8\(suffix)"
    }

    private func makeStore(now: @escaping @Sendable () -> Date = { Date() }) -> PendingGroupInviteStore {
        PendingGroupInviteStore(persistence: .inMemory(), now: now)
    }

    @Test func acceptsALinkAndHandsItBackByToken() {
        let store = makeStore()

        guard case .accepted(let token) = store.put(Self.link("a")) else {
            Issue.record("a group link is accepted")
            return
        }

        #expect(store.link(for: token) == Self.link("a"))
        #expect(store.newestToken() == token)
    }

    @Test func refusesWhatIsNotAGroupLink() {
        let store = makeStore()

        #expect(store.put("https://gift.justzappit.xyz/c/v1#abc") == .refused)
        #expect(store.put("") == .refused)
        #expect(store.newestToken() == nil)
    }

    @Test func theSameLinkTwiceIsAlreadyPending() {
        let store = makeStore()

        guard case .accepted = store.put(Self.link("a")) else {
            Issue.record("the first tap is accepted")
            return
        }

        #expect(store.put(Self.link("a")) == .alreadyPending)
    }

    /// Newest first, so a flood of links drops the oldest rather than the one just tapped.
    @Test func keepsOnlyTheFourNewest() {
        let store = makeStore()
        var tokens: [String] = []

        for index in 0..<6 {
            guard case .accepted(let token) = store.put(Self.link("\(index)")) else {
                Issue.record("each distinct link is accepted")
                return
            }
            tokens.append(token)
        }

        #expect(store.link(for: tokens[5]) == Self.link("5"))
        #expect(store.link(for: tokens[0]) == nil)
        #expect(store.newestToken() == tokens[5])
    }

    @Test func anInviteNobodyOpenedLapsesAfterSevenDays() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = MutableClock(now: start)
        let store = makeStore(now: { clock.now })

        guard case .accepted(let token) = store.put(Self.link("a")) else {
            Issue.record("the link is accepted")
            return
        }

        clock.now = start.addingTimeInterval(6 * 24 * 60 * 60)
        #expect(store.link(for: token) == Self.link("a"))

        clock.now = start.addingTimeInterval(8 * 24 * 60 * 60)
        #expect(store.link(for: token) == nil)
        #expect(store.newestToken() == nil)
    }

    @Test func removeSpendsOneInviteAndClearWipesThemAll() {
        let store = makeStore()

        guard case .accepted(let first) = store.put(Self.link("a")),
              case .accepted(let second) = store.put(Self.link("b")) else {
            Issue.record("both links are accepted")
            return
        }

        store.remove(token: first)
        #expect(store.link(for: first) == nil)
        #expect(store.link(for: second) == Self.link("b"))

        store.clear()
        #expect(store.newestToken() == nil)
    }
}

/// A clock a test can move, since an expiry test cannot wait a week.
private final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Date

    init(now: Date) {
        self.stored = now
    }

    var now: Date {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
