// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
import Testing
@testable import zodl_internal

/// What the screen may say about a number it did not compute. The limit is the Diamond's, a read
/// failure is ours rather than the user's, and a locked limit is a word rather than a rendered $0.
struct ReputationStoreTests {
    @MainActor @Test func aFirstLoadThatFailsSaysSoRatherThanShowingAZeroedSummary() async {
        let store = await TestStore(initialState: .initial(currencyCode: "INR")) { Reputation() } withDependencies: {
            $0.reputation.summary = { _ in throw Failure.unreachable }
        }

        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.loadFailed) {
            $0.isLoading = false
            $0.content = .unreadable
        }

        #expect(store.state.primaryAction == .retry)
        // Still lets them into the verification list: the read failure is ours, not theirs.
        #expect(store.state.isRaiseLimitVisible)
    }

    /// A failed *refresh* leaves the last good read on screen: it was true a moment ago, and
    /// blanking it over a dropped request is the worse lie.
    @MainActor @Test func aFailedRefreshKeepsWhatWasAlreadyRead() async {
        let ready = ReputationFixtures.summary(canBuy: true, buyLimitMicros: "100000000")
        var state = Reputation.State.initial(currencyCode: "INR")
        state.content = .ready(ready)

        let store = await TestStore(initialState: state) { Reputation() } withDependencies: {
            $0.reputation.summary = { _ in throw Failure.unreachable }
        }

        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.loadFailed) { $0.isLoading = false }

        #expect(store.state.content == .ready(ready))
        #expect(store.state.primaryAction == .buy)
    }

    @MainActor @Test func aColdWalletIsLockedRatherThanShownAZeroLimit() async {
        let store = await TestStore(initialState: .initial(currencyCode: "INR")) { Reputation() } withDependencies: {
            $0.reputation.summary = { _ in ReputationFixtures.summary(canBuy: false, buyLimitMicros: "0") }
        }

        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.summaryLoaded) {
            $0.isLoading = false
            $0.content = .ready(ReputationFixtures.summary(canBuy: false, buyLimitMicros: "0"))
        }

        #expect(store.state.buyLimitText == String(localizable: .reputationLimitLocked))
        #expect(store.state.buyLimitCaption == String(localizable: .reputationLimitLockedCaption))
        #expect(store.state.primaryAction == .verifyToBuy)
        // Raising the limit would duplicate the primary, so it is absent.
        #expect(!store.state.isRaiseLimitVisible)
    }

    @MainActor @Test func aWalletThatCanBuyShowsTheDiamondsOwnNumber() async {
        let store = await TestStore(initialState: .initial(currencyCode: "INR")) { Reputation() } withDependencies: {
            $0.reputation.summary = { _ in ReputationFixtures.summary(canBuy: true, buyLimitMicros: "150500000") }
        }

        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.summaryLoaded) {
            $0.isLoading = false
            $0.content = .ready(ReputationFixtures.summary(canBuy: true, buyLimitMicros: "150500000"))
        }

        #expect(store.state.buyLimitText == String(localizable: .reputationAmountUsd("150.5")))
        #expect(store.state.buyLimitCaption == String(localizable: .reputationLimitCaption))
        #expect(store.state.primaryAction == .buy)
        #expect(store.state.isRaiseLimitVisible)
    }

    /// At the ceiling a further verification buys nothing, so the offer is withdrawn and the
    /// caption says why.
    @MainActor @Test func atTheCeilingNothingIsOfferedBeyondBuying() async {
        let ceiling = ReputationFixtures.summary(canBuy: true, buyLimitMicros: "400000000", isAtCeiling: true)
        let store = await TestStore(initialState: .initial(currencyCode: "INR")) { Reputation() } withDependencies: {
            $0.reputation.summary = { _ in ceiling }
        }

        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.summaryLoaded) {
            $0.isLoading = false
            $0.content = .ready(ceiling)
        }

        #expect(store.state.buyLimitCaption == String(localizable: .reputationLimitCaptionAtCeiling))
        #expect(!store.state.isRaiseLimitVisible)
    }

    /// Terminal: verifying will not change it, so the screen offers nothing to press.
    @MainActor @Test func aBlacklistedWalletIsOfferedNoActionAtAll() async {
        let store = await TestStore(initialState: .initial(currencyCode: "INR")) { Reputation() } withDependencies: {
            $0.reputation.summary = { _ in ReputationFixtures.summary(canBuy: false, buyLimitMicros: "0", isBlocked: true) }
        }

        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.summaryLoaded) {
            $0.isLoading = false
            $0.content = .blocked
        }

        #expect(store.state.primaryAction == nil)
        #expect(!store.state.isRaiseLimitVisible)
    }

    /// A screen that reloads on every appearance must not stack reads onto itself.
    @MainActor @Test func aSecondLoadWhileOneIsInFlightIsIgnored() async {
        let calls = LockIsolated(0)
        let clock = TestClock()
        let store = await TestStore(initialState: .initial(currencyCode: "INR")) { Reputation() } withDependencies: {
            $0.reputation.summary = { _ in
                calls.withValue { $0 += 1 }
                try await clock.sleep(for: .seconds(1))
                return ReputationFixtures.summary(canBuy: true, buyLimitMicros: "100000000")
            }
        }

        await store.send(.onAppear) { $0.isLoading = true }
        await store.send(.retryTapped)
        await clock.advance(by: .seconds(1))
        await store.receive(\.summaryLoaded) {
            $0.isLoading = false
            $0.content = .ready(ReputationFixtures.summary(canBuy: true, buyLimitMicros: "100000000"))
        }

        #expect(calls.value == 1)
    }

    @MainActor @Test func buyingCarriesTheCorridorTheLimitWasReadFor() async {
        var state = Reputation.State.initial(currencyCode: "BRL")
        state.content = .ready(ReputationFixtures.summary(canBuy: true, buyLimitMicros: "100000000"))
        let store = await TestStore(initialState: state) { Reputation() }

        await store.send(.buyTapped)
        await store.receive(\.delegate.buy)
    }

    @MainActor @Test func verifyingToBuyRoutesToTheListThatRaisesTheLimit() async {
        var state = Reputation.State.initial(currencyCode: "INR")
        state.content = .ready(ReputationFixtures.summary(canBuy: false, buyLimitMicros: "0"))
        let store = await TestStore(initialState: state) { Reputation() }

        await store.send(.raiseLimitTapped)
        await store.receive(\.delegate.raiseLimit)
    }

    private enum Failure: Error { case unreachable }
}

enum ReputationFixtures {
    static func summary(
        canBuy: Bool,
        buyLimitMicros: String,
        isAtCeiling: Bool = false,
        isBlocked: Bool = false,
        platforms: [ReputationPlatformModel] = ReputationFixtures.platforms
    ) -> ReputationSummaryModel {
        ReputationSummaryModel(
            currencyCode: "INR",
            points: "100",
            isBlocked: isBlocked,
            canBuy: canBuy,
            isAtCeiling: isAtCeiling,
            buyLimitMicros: buyLimitMicros,
            maxBuyLimitMicros: "400000000",
            platforms: platforms
        )
    }

    // Measured on Base mainnet: LinkedIn is worth double and leads every list.
    static let platforms: [ReputationPlatformModel] = [
        platform(id: "LinkedIn", award: "100", gain: "100000000"),
        platform(id: "X", award: "50", gain: "50000000", requiresMatureAccount: true),
        platform(id: "GitHub", award: "50", gain: "50000000", requiresMatureAccount: true),
        platform(id: "Instagram", award: "50", gain: "50000000", requiresMatureAccount: true),
        platform(id: "Facebook", award: "50", gain: "50000000"),
        platform(id: "Binance", award: "50", gain: "50000000")
    ]

    static func platform(
        id: String,
        award: String,
        gain: String?,
        isVerified: Bool = false,
        requiresMatureAccount: Bool = false
    ) -> ReputationPlatformModel {
        ReputationPlatformModel(
            id: id,
            name: id,
            awardPoints: award,
            isVerified: isVerified,
            requiresMatureAccount: requiresMatureAccount,
            limitGainMicros: isVerified ? nil : gain
        )
    }
}
