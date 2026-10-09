//
//  YouTabParityTests.swift
//  zodlTests
//
//  The You tab's live rows, matched to Android's `TabsVM`: the P2P payment method and local
//  currency subtitles name what is selected, and the Base account row says when a cash-out is
//  still running.
//

import ComposableArchitecture
import Foundation
import Testing
@testable import zodl_internal

@Suite(.serialized) struct YouTabParityTests {
    private func youState() -> ZappTabs.State {
        var state = ZappTabs.State()
        state.selectedTab = .you
        return state
    }

    private func run(_ id: String, statuses: [PeerProgress] = []) -> PeerRun {
        PeerRun(
            id: id,
            destinationCode: "revolut",
            amount: UsdcAmount(micros: "20000000") ?? .zero,
            currencyCodes: ["EUR"],
            startedAt: Date(timeIntervalSince1970: 0),
            statuses: statuses
        )
    }

    private func progress(depositID: String?) -> PeerProgress {
        PeerProgress(
            subjectID: "a",
            kind: .orderLive,
            step: .awaitingBuyer,
            amount: nil,
            txHash: nil,
            depositID: depositID,
            order: nil,
            failure: nil,
            isTerminal: false
        )
    }

    private func order(_ id: String, isFinished: Bool) -> PeerOrder {
        PeerOrder(
            depositID: "escrow_\(id)",
            phase: isFinished ? .closed : .waiting,
            isFinished: isFinished,
            acceptingIntents: !isFinished,
            gross: UsdcAmount(micros: "20000000") ?? .zero,
            remaining: UsdcAmount(micros: "20000000") ?? .zero,
            sold: .zero,
            locked: .zero,
            withdrawn: .zero,
            withdrawable: .zero,
            destinationCode: "revolut",
            currencyCodes: ["EUR"],
            buyerLegs: [],
            offersWithdrawal: false,
            offersMatchingToggle: false,
            isHiddenFromBuyers: false,
            openedAt: Date(timeIntervalSince1970: 0),
            lastActivityAt: Date(timeIntervalSince1970: 0),
            explorerURL: nil
        )
    }

    @MainActor @Test func theYouTabNamesTheSelectedCorridorAndCurrency() async {
        let store = TestStore(initialState: youState()) {
            ZappTabs()
        } withDependencies: {
            $0.defaultInMemoryStorage = .init()
            $0.userStoredPreferences.exchangeRate = { .init(manual: false, automatic: true, currency: .eur) }
            $0.userStoredPreferences.p2pRail = { .scanAndPay(currencyCode: "BRL") }
            $0.offramp.corridors = {
                [
                    OfframpCorridor(
                        currencyCode: "BRL",
                        countryName: "Brazil",
                        paymentRail: "PIX",
                        flag: "🇧🇷",
                        symbol: "R$",
                        precision: 2
                    )
                ]
            }
            $0.peerCashOut.isConfigured = { false }
        }

        await store.send(.youTabAppeared) {
            $0.localCurrency = .init(manual: false, automatic: true, currency: .eur)
            $0.p2pRail = .scanAndPay(currencyCode: "BRL")
        }
        await store.receive(.p2pRailSubtitleLoaded(
            .scanAndPay(currencyCode: "BRL"),
            String(localizable: .settingsYouP2pRailSubtitle("PIX", "Brazil"))
        )) {
            $0.p2pRailSubtitle = String(localizable: .settingsYouP2pRailSubtitle("PIX", "Brazil"))
        }
        await store.send(.youTabDisappeared)
    }

    @MainActor @Test func aCashOutRailSummarisesItsCurrenciesLikeAndroid() {
        let destination = PeerDestination(
            code: "revolut",
            currencies: ["EUR", "USD", "GBP", "CHF"].map { PeerFiatCurrency(code: $0, symbol: $0, precision: 2) },
            defaultCurrencyCodes: ["EUR", "USD"],
            validatesHandleLive: true,
            offersCurrencyChoice: true
        )

        #expect(
            ZappTabs.currencySummary(destination)
                == String(localizable: .settingsYouP2pRailCurrenciesMore("EUR, USD", 2))
        )
    }

    /// A pushed screen covers the tab without unmounting it, so Root re-sends `youTabAppeared` on
    /// close. It must stay inert while another tab is showing.
    @MainActor @Test func reloadingIsIgnoredOnOtherTabs() async {
        var state = ZappTabs.State()
        state.selectedTab = .pay
        let store = TestStore(initialState: state) {
            ZappTabs()
        } withDependencies: {
            $0.defaultInMemoryStorage = .init()
        }

        await store.send(.youTabAppeared)
    }

    @MainActor @Test func anUnindexedAttemptMarksTheBaseAccountRowUntilItSettles() async {
        let (stream, continuation) = AsyncStream<PeerRunnerState>.makeStream()
        let orderReads = LockIsolated(0)
        let store = TestStore(initialState: youState()) {
            ZappTabs()
        } withDependencies: {
            $0.defaultInMemoryStorage = .init()
            $0.userStoredPreferences.exchangeRate = { nil }
            $0.userStoredPreferences.p2pRail = { nil }
            $0.offramp.corridors = { [] }
            $0.peerCashOut.isConfigured = { true }
            $0.continuousClock = TestClock()
            $0.peerCashOut.runnerState = { stream }
            $0.peerCashOut.orderHistory = {
                orderReads.withValue { $0 += 1 }
                return []
            }
        }
        store.exhaustivity = .off

        await store.send(.youTabAppeared)
        await store.receive(\.activePeerOrdersLoaded)
        #expect(!store.state.hasPeerActivity)

        continuation.yield(PeerRunnerState(runs: [run("a")]))
        await store.receive(\.peerRunsChanged)
        #expect(store.state.hasPeerActivity)
        // The attempt now holds funds, which is when Android re-reads the chain.
        await store.receive(\.activePeerOrdersLoaded)
        #expect(orderReads.value == 2)

        continuation.finish()
        await store.send(.youTabDisappeared)
    }

    @Test func onlyUnfinishedOrdersAndUnfailedAttemptsCountAsActivity() {
        withDependencies {
            $0.defaultInMemoryStorage = .init()
        } operation: {
            var state = youState()
            #expect(!state.hasPeerActivity)

            state.activePeerOrderCount = 1
            #expect(state.hasPeerActivity)

            state.activePeerOrderCount = 0
            state.peerRuns = [run("a", statuses: [progress(depositID: "escrow_a")])]
            // A receipt's deposit ID does not mean the indexer has caught up.
            #expect(state.hasPeerActivity)

            state.indexedPeerDepositIDs = ["escrow_a"]
            #expect(!state.hasPeerActivity)

            state.peerRuns = [run("a")]
            #expect(state.hasPeerActivity)
        }
    }

    @MainActor @Test func finishedOrdersAreNotOnOffer() async {
        let store = TestStore(initialState: youState()) {
            ZappTabs()
        } withDependencies: {
            $0.defaultInMemoryStorage = .init()
            $0.userStoredPreferences.exchangeRate = { nil }
            $0.userStoredPreferences.p2pRail = { nil }
            $0.offramp.corridors = { [] }
            $0.peerCashOut.isConfigured = { true }
            $0.continuousClock = TestClock()
            $0.peerCashOut.runnerState = { AsyncStream { $0.finish() } }
            $0.peerCashOut.orderHistory = { [order("a", isFinished: true), order("b", isFinished: false)] }
        }
        store.exhaustivity = .off

        await store.send(.youTabAppeared)
        await store.receive(\.activePeerOrdersLoaded) {
            $0.activePeerOrderCount = 1
            $0.indexedPeerDepositIDs = ["escrow_a", "escrow_b"]
        }
        await store.send(.youTabDisappeared)
    }

    @MainActor @Test func pollingKeepsAReceiptVisibleUntilIndexedAndClearsItWhenTheOrderFinishes() async {
        let clock = TestClock()
        let orders = LockIsolated<[PeerOrder]>([])
        let reads = LockIsolated(0)
        let storage = InMemoryStorage()
        let state = withDependencies {
            $0.defaultInMemoryStorage = storage
        } operation: {
            var state = youState()
            state.peerRuns = [run("a", statuses: [progress(depositID: "escrow_a")])]
            return state
        }
        let store = TestStore(initialState: state) {
            ZappTabs()
        } withDependencies: {
            $0.defaultInMemoryStorage = storage
            $0.continuousClock = clock
            $0.userStoredPreferences.exchangeRate = { nil }
            $0.userStoredPreferences.p2pRail = { nil }
            $0.offramp.corridors = { [] }
            $0.peerCashOut.isConfigured = { true }
            $0.peerCashOut.runnerState = { AsyncStream { $0.finish() } }
            $0.peerCashOut.orderHistory = {
                reads.withValue { $0 += 1 }
                return orders.value
            }
        }

        await store.send(.youTabAppeared)
        await store.receive(.activePeerOrdersLoaded([]))
        #expect(store.state.hasPeerActivity)

        let active = order("a", isFinished: false)
        orders.setValue([active])
        await clock.advance(by: .seconds(15))
        await store.receive(.activePeerOrdersLoaded([active])) {
            $0.activePeerOrderCount = 1
            $0.indexedPeerDepositIDs = ["escrow_a"]
        }
        #expect(store.state.hasPeerActivity)

        let finished = order("a", isFinished: true)
        orders.setValue([finished])
        await clock.advance(by: .seconds(15))
        await store.receive(.activePeerOrdersLoaded([finished])) {
            $0.activePeerOrderCount = 0
        }
        #expect(!store.state.hasPeerActivity)

        orders.setValue([])
        await clock.advance(by: .seconds(15))
        await store.receive(.activePeerOrdersLoaded([]))
        #expect(!store.state.hasPeerActivity)
        #expect(reads.value == 4)

        await store.send(.youTabDisappeared)
        await clock.advance(by: .seconds(30))
        #expect(reads.value == 4)
        await store.finish()
    }
}
