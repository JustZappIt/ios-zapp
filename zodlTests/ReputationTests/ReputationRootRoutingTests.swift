// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
import Testing
@testable import zodl_internal

@Suite(.serialized)
@MainActor
struct ReputationRootRoutingTests {
    @Test(arguments: [false, true])
    func buyRoutesAccordingToTheSelectedCorridorsReputation(canBuy: Bool) async {
        let currencies = LockIsolated<[String]>([])
        let summary = ReputationFixtures.summary(canBuy: canBuy, buyLimitMicros: canBuy ? "200000000" : "0")
        let store = makeStore { currency in
            currencies.withValue { $0.append(currency) }
            return summary
        }
        await store.send(.home(.buyTapped))
        await store.receive(\.buyReputationLoaded)
        #expect(currencies.value == ["BRL"])
        #expect(store.state.path == (canBuy ? .onramp : .reputation))
        #expect(store.state.onrampState.currencyCode == "BRL")
        if !canBuy {
            #expect(store.state.reputationState.currencyCode == "BRL")
            #expect(store.state.reputationState.content == .ready(summary))
            await store.send(.reputation(.delegate(.close)))
            #expect(store.state.path == nil)
        }
    }

    @Test func aBlockedWalletOpensTheBlockedScreen() async {
        let store = makeStore { _ in
            ReputationFixtures.summary(canBuy: false, buyLimitMicros: "0", isBlocked: true)
        }
        await store.send(.home(.buyTapped))
        await store.receive(\.buyReputationLoaded)
        #expect(store.state.path == .reputation)
        #expect(store.state.reputationState.content == .blocked)
    }

    @Test func anUnreadableChainStillAllowsTheAmountScreen() async {
        let store = makeStore { _ in throw Failure.network }
        await store.send(.home(.buyTapped))
        await store.receive(\.buyReputationLoaded)
        #expect(store.state.path == .onramp)
        #expect(store.state.onrampState.currencyCode == "BRL")
        #expect(store.state.buyReputationRequestID == nil)
    }

    @Test func aSecondBuyTapDoesNotStackReadsOrOverwriteAnotherScreen() async {
        let started = AsyncStream<Void>.makeStream()
        var starts = started.stream.makeAsyncIterator()
        let responses = AsyncStream<ReputationSummaryModel>.makeStream()
        let calls = LockIsolated(0)
        let store = makeStore { _ in
            calls.withValue { $0 += 1 }
            started.continuation.yield(())
            for await summary in responses.stream { return summary }
            throw CancellationError()
        }
        await store.send(.home(.buyTapped))
        await starts.next()
        await store.send(.home(.buyTapped))
        // Another user navigation wins over the pending read.
        await store.send(.onramp(.delegate(.openReputation)))
        responses.continuation.yield(ReputationFixtures.summary(canBuy: true, buyLimitMicros: "200000000"))
        await store.receive(\.buyReputationLoaded)
        #expect(calls.value == 1)
        #expect(store.state.path == .reputation)
        #expect(store.state.buyReputationRequestID == nil)
    }

    @Test func aResultForAnAccountThatIsNoLongerSelectedDoesNotNavigate() {
        withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = Root.State.initial
            let requestID = UUID()
            state.buyReputationRequestID = requestID
            _ = Root().coordinatorReduce()._reduce(into: &state, action: .buyReputationLoaded(
                requestID: requestID,
                currencyCode: "BRL",
                accountID: [UInt8](repeating: 7, count: 16),
                summary: ReputationFixtures.summary(canBuy: true, buyLimitMicros: "200000000")
            ))
            #expect(state.path == nil)
            #expect(state.buyReputationRequestID == nil)
        }
    }

    @Test func theLimitInfoDetourReturnsToTheOriginalAmount() async {
        let store = makeStore { _ in throw Failure.network }
        await store.send(.home(.buyTapped))
        await store.receive(\.buyReputationLoaded)
        await store.send(.onramp(.amountChanged("123.45")))
        await store.send(.onramp(.delegate(.openReputation)))
        #expect(store.state.reputationReturnPath == .onramp)
        #expect(store.state.reputationState.currencyCode == "BRL")
        await store.send(.reputation(.delegate(.close)))
        #expect(store.state.path == .onramp)
        #expect(store.state.onrampState.amount == "123.45")
    }

    @Test func aColdReturnReconstructsTheSessionOnce() async {
        let store = makeStore { _ in throw Failure.network }
        await store.send(.reclaimReturnReceived(Self.resume))
        #expect(store.state.path == .increaseReputation)
        #expect(store.state.increaseReputationState.resumeSessionID == "session-123")
        #expect(store.state.increaseReputationState.resumePlatformID == "GitHub")
        #expect(store.state.increaseReputationState.currencyCode == "BRL")
        #expect(!store.state.canRecoverReclaimOnLaunch)
        await store.send(.increaseReputation(.delegate(.close)))
        await store.send(.reputation(.delegate(.close)))
        await store.send(.reclaimReturnReceived(Self.resume))
        #expect(store.state.path == nil)
    }

    @Test func aCanceledRunIsNotReopenedByALateReturn() async {
        let store = makeStore { _ in throw Failure.network }
        await store.send(.home(.onAppear))
        await store.send(.reputation(.delegate(.raiseLimit(currencyCode: "BRL"))))
        await store.send(.increaseReputation(.delegate(.close)))
        await store.send(.reputation(.delegate(.close)))
        await store.send(.reclaimReturnReceived(Self.resume))
        #expect(store.state.path == nil)
        #expect(store.state.increaseReputationState.resumeSessionID == nil)
    }

    @Test func aWarmReturnDoesNotReplaceTheScreenOnDisplay() async {
        let store = makeStore { _ in throw Failure.network }
        await store.send(.home(.onAppear))
        await store.send(.onramp(.delegate(.openReputation)))
        await store.send(.reclaimReturnReceived(Self.resume))
        #expect(store.state.path == .reputation)
        #expect(store.state.increaseReputationState.resumeSessionID == nil)
    }

    @Test func backgroundingBeforeHomeStillClosesLaunchRecovery() async {
        let store = makeStore { _ in throw Failure.network }
        await store.send(.initialization(.appDelegate(.didEnterBackground)))
        await store.send(.reclaimReturnReceived(Self.resume))
        #expect(store.state.path == nil)
        #expect(store.state.increaseReputationState.resumeSessionID == nil)
    }

    private static let resume = ReclaimReturnLink.ResumeArgs(sessionID: "session-123", platformID: "GitHub", currencyCode: "BRL")
    private enum Failure: Error { case network }

    private func makeStore(
        summary: @escaping @Sendable (String) async throws -> ReputationSummaryModel
    ) -> TestStore<Root.State, Root.Action> {
        withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = Root.State.initial
            state.offrampState.selectedCurrencyCode = "BRL"
            let store = TestStore(initialState: state) {
                CombineReducers {
                    Scope<Root.State, Root.Action, Onramp>(state: \.onrampState, action: \.onramp) { Onramp() }
                    Root().coordinatorReduce()
                }
            } withDependencies: {
                $0.reputation.summary = summary
                $0.onramp.isConfigured = { true }
                $0.uuid = .incrementing
            }
            store.exhaustivity = .off
            return store
        }
    }
}
