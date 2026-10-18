// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
import Testing
@testable import zodl_internal

@Suite(.serialized, .timeLimit(.minutes(1))) @MainActor
struct OfframpFundingTests {
    @Test func aFreshPayableQuoteClearsTheEmptyWalletPanel() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let store = quoteStore()
            #expect(store.state.showsPayAddFundsPanel)

            await store.send(.quoteLoaded(quote()))

            #expect(store.state.quote?.canPayFromBase == true)
            #expect(store.state.baseUsdc == 5)
            #expect(store.state.baseBalanceDisplay == "5")
            #expect(!store.state.showsPayAddFundsPanel)

            // Editing the amount clears the quote, but must not forget its fresh balance.
            await store.send(.fiatAmountChanged("200"))
            #expect(store.state.quote == nil)
            #expect(!store.state.showsPayAddFundsPanel)
        }
    }

    @Test func theCommitTimeQuoteAlsoRefreshesFunding() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = emptyState()
            state.isLoading = true
            let store = quoteStore(state: state)

            await store.send(.payQuoteRefreshed(quote()))

            #expect(store.state.isPayConfirmationPresented)
            #expect(store.state.baseUsdc == 5)
            #expect(!store.state.showsPayAddFundsPanel)
        }
    }

    @Test func aQuoteRetainsTheFullPrecisionOfTheLocalizedBaseBalance() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let store = quoteStore()
            let balance = UsdcAmount(micros: "500001") ?? .zero
            await store.send(.quoteLoaded(quote(baseBalanceDisplay: balance.display)))

            #expect(store.state.baseUsdc == Decimal(500001) / 1_000_000)
            #expect(!store.state.showsPayAddFundsPanel)
        }
    }

    @Test func anEarlierAccountReadDoesNotReplaceTheFreshQuoteBalance() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let store = quoteStore()
            await store.send(.quoteLoaded(quote()))

            await store.send(.accountLoaded(Self.account(balanceMicros: "0")))

            #expect(store.state.baseUsdc == 5)
            #expect(!store.state.showsPayAddFundsPanel)
        }
    }

    @Test func aZeroAvailableQuoteDoesNotHideReservedBaseFunds() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = emptyState()
            state.account = Self.account(balanceMicros: "5000000")
            let store = quoteStore(state: state)
            await store.send(.quoteLoaded(quote(baseBalanceDisplay: "0", canPayFromBase: false)))

            #expect(store.state.baseUsdc == 5)
            #expect(!store.state.showsPayAddFundsPanel)
        }
    }

    @Test func incomingBaseFundsUnblockTheVisiblePanelAndStopPolling() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let clock = TestClock()
            let reads = LockIsolated(0)
            let store = fundingStore(clock: clock, reads: reads)

            await store.send(.onAppear)
            await store.receive(\.accountLoaded)
            #expect(store.state.isFundingObservationActive)
            #expect(store.state.showsPayAddFundsPanel)

            await clock.advance(by: .seconds(10))
            await store.receive(\.baseFundingRefreshed)

            #expect(store.state.account?.balanceMicros == "5000000")
            #expect(!store.state.showsPayAddFundsPanel)
            #expect(store.state.quote == nil)
            await clock.advance(by: .seconds(30))
            #expect(reads.value == 2)
            await store.send(.onDisappear)
            await store.finish()
        }
    }

    @Test(arguments: [false, true])
    func leavingTheScreenStopsFundingReads(cancelAll: Bool) async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let clock = TestClock()
            let reads = LockIsolated(0)
            let store = fundingStore(clock: clock, reads: reads)

            await store.send(.onAppear)
            await store.receive(\.accountLoaded)
            #expect(store.state.showsPayAddFundsPanel)
            #expect(reads.value == 1)

            await store.send(cancelAll ? .cancelAll : .onDisappear)
            await clock.advance(by: .seconds(30))
            #expect(!store.state.isFundingObservationActive)
            #expect(reads.value == 1)

            // Also reject a read that was already queued when the screen closed.
            await store.send(.baseFundingRefreshed(Self.account(balanceMicros: "5000000")))
            #expect(store.state.account?.balanceMicros == "0")
            await store.finish()
        }
    }

    @Test func aFailedReadRetriesWithoutChangingTheKnownBalance() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let clock = TestClock()
            let reads = LockIsolated(0)
            let readStarted = AsyncStream<Int>.makeStream()
            let store = fundingStore(clock: clock, reads: reads)
            store.dependencies.offramp.accountSummary = {
                let attempt = reads.withValue { $0 += 1; return $0 }
                readStarted.continuation.yield(attempt)
                if attempt == 2 { throw URLError(.notConnectedToInternet) }
                return Self.account(balanceMicros: attempt == 1 ? "0" : "5000000")
            }

            await store.send(.onAppear)
            await store.receive(\.accountLoaded)
            var started = readStarted.stream.makeAsyncIterator()
            #expect(await started.next() == 1)

            await clock.advance(by: .seconds(10))
            #expect(await started.next() == 2)
            #expect(store.state.account?.balanceMicros == "0")
            #expect(store.state.showsPayAddFundsPanel)

            await clock.advance(by: .seconds(10))
            await store.receive(\.baseFundingRefreshed)
            #expect(store.state.account?.balanceMicros == "5000000")
            #expect(!store.state.showsPayAddFundsPanel)
            await store.send(.onDisappear)
            await store.finish()
        }
    }

    private func quoteStore(state: Offramp.State? = nil) -> TestStoreOf<Offramp> {
        let store = TestStore(initialState: state ?? emptyState()) { Offramp() }
        store.exhaustivity = .off
        return store
    }

    private func fundingStore(clock: TestClock<Duration>, reads: LockIsolated<Int>) -> TestStoreOf<Offramp> {
        var state = emptyState()
        state.quote = quote(baseBalanceDisplay: "0", canPayFromBase: false)
        let store = TestStore(initialState: state) { Offramp() } withDependencies: {
            $0.continuousClock = clock
            $0.offramp.corridors = { [] }
            $0.offramp.checkpointCurrencyCode = { nil }
            $0.offramp.topUpCheckpointMicros = { nil }
            $0.offramp.resetScreen = { }
            $0.offramp.accountSummary = {
                let attempt = reads.withValue { $0 += 1; return $0 }
                return Self.account(balanceMicros: attempt == 1 ? "0" : "5000000")
            }
        }
        store.exhaustivity = .off
        return store
    }

    private func emptyState() -> Offramp.State {
        var state = Offramp.State(page: .amount, corridorContext: .payment)
        state.$walletFunding.withLock { $0 = .empty }
        state.account = Self.account(balanceMicros: "0")
        state.fiatAmount = "100"
        return state
    }

    private nonisolated static func account(balanceMicros: String) -> OfframpAccountModel {
        OfframpAccountModel(
            address: "0xabc",
            balanceMicros: balanceMicros,
            balanceDisplay: nil,
            explorerURL: nil,
            canBridgeToBase: true,
            canRefundToZec: true
        )
    }

    private func quote(baseBalanceDisplay: String = "5", canPayFromBase: Bool = true) -> OfframpQuoteModel {
        OfframpQuoteModel(
            currencyCode: "INR",
            fiatAmount: "100",
            usdcMicros: "1000000",
            usdcDisplay: "1",
            sellRate: "100",
            fixedFeeDisplay: "0",
            requiredBalanceMicros: "1000000",
            baseBalanceDisplay: baseBalanceDisplay,
            shortfallMicros: "0",
            shortfallDisplay: "0",
            canPayFromBase: canPayFromBase,
            canBridgeToBase: true
        )
    }
}
