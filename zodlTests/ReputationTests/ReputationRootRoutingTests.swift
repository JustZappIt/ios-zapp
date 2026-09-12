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
        await openBuy(store)
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
        await openBuy(store)
        await store.receive(\.buyReputationLoaded)
        #expect(store.state.path == .reputation)
        #expect(store.state.reputationState.content == .blocked)
    }

    @Test func anUnreadableChainKeepsVerificationAndRetryReachable() async {
        let store = makeStore { _ in throw Failure.network }
        await openBuy(store)
        await store.receive(\.buyReputationLoaded)
        #expect(store.state.path == .reputation)
        #expect(store.state.reputationState.content == .unreadable)
        #expect(store.state.reputationState.primaryAction == .retry)
        #expect(store.state.reputationState.isRaiseLimitVisible)
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
        await openBuy(store)
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
            state.path = .reputation
            state.reputationState = .initial(currencyCode: "BRL", isBuyEntry: true)
            state.reputationState.isLoading = true
            state.buyReputationRequestID = requestID
            _ = Root().coordinatorReduce()._reduce(into: &state, action: .buyReputationLoaded(
                requestID: requestID,
                currencyCode: "BRL",
                accountID: [UInt8](repeating: 7, count: 16),
                hasCheckpoint: false,
                summary: ReputationFixtures.summary(canBuy: true, buyLimitMicros: "200000000")
            ))
            #expect(state.path == .reputation)
            #expect(state.reputationState.content == .unreadable)
            #expect(!state.reputationState.isLoading)
            #expect(state.buyReputationRequestID == nil)
        }
    }

    @Test func theLimitInfoDetourReturnsToTheOriginalAmount() async {
        let store = makeStore { _ in ReputationFixtures.summary(canBuy: true, buyLimitMicros: "200000000") }
        await openBuy(store)
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
        #expect(store.state.increaseReputationState.requiresResumeConfirmation)
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

    @Test(arguments: [false, true])
    func aFirstTimeZeroReputationWalletMustVerifyEvenWithADefaultLimit(canBuy: Bool) async {
        let summary = ReputationFixtures.summary(canBuy: canBuy, buyLimitMicros: "100000000", points: "0")
        let store = makeStore { _ in summary }
        await store.send(.home(.buyTapped))
        #expect(store.state.path == .reputation)
        #expect(store.state.reputationState.content == .loading)
        await store.send(.reputation(.onAppear))
        await store.receive(\.buyReputationLoaded)
        #expect(store.state.reputationState.primaryAction == .verifyToBuy)
        await store.send(.reputation(.buyTapped))
        #expect(store.state.path == .reputation)
        await store.send(.reputation(.raiseLimitTapped))
        await store.receive(\.reputation.delegate.raiseLimit)
        #expect(store.state.path == .increaseReputation)
        await store.send(.increaseReputation(.onAppear))
        await store.receive(\.increaseReputation.summaryLoaded)
        #expect(store.state.increaseReputationState.platforms.contains { $0.id == "LinkedIn" && !$0.isVerified })
    }

    @Test func retryChecksAgainInsteadOfBypassingVerification() async {
        let calls = LockIsolated(0)
        let store = makeStore { _ in
            calls.withValue { $0 += 1 }
            if calls.value == 1 { throw Failure.network }
            return ReputationFixtures.summary(canBuy: false, buyLimitMicros: "0", points: "0")
        }
        await openBuy(store)
        await store.receive(\.buyReputationLoaded)
        #expect(store.state.reputationState.content == .unreadable)
        await store.send(.reputation(.retryTapped))
        await store.receive(\.buyReputationLoaded)
        #expect(calls.value == 2)
        #expect(store.state.reputationState.primaryAction == .verifyToBuy)
    }

    @Test func anExistingPurchaseBypassesTheNewPurchaseGate() async {
        let checkpoint = OnrampCheckpointModel(
            id: "saved-purchase", phase: .completed, orderID: "42", destination: .zcash, zecDelivery: nil
        )
        let store = makeStore(checkpoint: checkpoint) { _ in
            Issue.record("Recovery must not depend on a new reputation check")
            return ReputationFixtures.summary(canBuy: false, buyLimitMicros: "0", isBlocked: true, points: "0")
        }
        await openBuy(store)
        await store.receive(\.buyReputationLoaded)
        #expect(store.state.path == .onramp)
    }

    @Test func anUnreadableCheckpointCannotBeTreatedAsNoPurchase() async {
        let store = makeStore(extra: { $0.onramp.checkpoint = { throw Failure.network } }) { _ in
            Issue.record("An unknown purchase must not be treated as a fresh purchase")
            return ReputationFixtures.summary(canBuy: true, buyLimitMicros: "200000000")
        }
        await openBuy(store)
        await store.receive(\.buyReputationLoaded)
        #expect(store.state.path == .reputation)
        #expect(store.state.reputationState.primaryAction == .retry)
    }

    @Test func completingVerificationUnlocksBuyOnReturn() async {
        let verified = LockIsolated(false)
        let store = makeStore { _ in
            ReputationFixtures.summary(
                canBuy: verified.value, buyLimitMicros: verified.value ? "200000000" : "0", points: verified.value ? "100" : "0"
            )
        }
        await openBuy(store)
        await store.receive(\.buyReputationLoaded)
        await store.send(.reputation(.raiseLimitTapped))
        await store.receive(\.reputation.delegate.raiseLimit)
        verified.setValue(true)
        await store.send(.increaseReputation(.delegate(.close)))
        await store.send(.reputation(.onAppear))
        await store.receive(\.buyReputationLoaded)
        #expect(store.state.path == .onramp)
    }

    @Test func restartingAResolvedPurchaseRequiresVerificationAgain() async {
        let saved = LockIsolated<OnrampCheckpointModel?>(OnrampCheckpointModel(
            id: "old-purchase", phase: .cancelled, orderID: "42", destination: .base, zecDelivery: nil
        ))
        let store = makeStore(extra: {
            $0.onramp.checkpoint = { saved.value }
            $0.onramp.clearCheckpoint = { saved.setValue(nil) }
        }) { _ in ReputationFixtures.summary(canBuy: false, buyLimitMicros: "0", points: "0") }
        await openBuy(store)
        await store.receive(\.buyReputationLoaded)
        #expect(store.state.path == .onramp)
        let cancelled = OnrampStatusModel(
            kind: .cancelled, phase: .cancelled, id: "old-purchase", orderID: "42", failureCode: nil, instruction: nil,
            fiatMicros: "100000000", netUsdcMicros: nil, recipientAddress: nil, paidTransactionHash: nil, expiresAt: nil, isTerminal: true
        )
        await store.send(.onramp(.statusReceived(cancelled)))
        await store.send(.onramp(.retryTapped))
        await store.receive(\.onramp)
        #expect(saved.value == nil)
        #expect(store.state.path == .reputation)
        await store.send(.reputation(.onAppear))
        await store.receive(\.buyReputationLoaded)
        #expect(store.state.reputationState.primaryAction == .verifyToBuy)
    }

    @Test func closingTheLoadingScreenCancelsItsNavigation() async {
        let started = AsyncStream<Void>.makeStream()
        var starts = started.stream.makeAsyncIterator()
        let responses = AsyncStream<ReputationSummaryModel>.makeStream()
        let store = makeStore { _ in
            started.continuation.yield(())
            for await response in responses.stream { return response }
            throw CancellationError()
        }
        await openBuy(store)
        await starts.next()
        await store.send(.reputation(.backTapped))
        await store.receive(\.reputation.delegate.close)
        await store.finish()
        #expect(store.state.path == nil)
        #expect(store.state.buyReputationRequestID == nil)
    }

    private func openBuy(_ store: TestStore<Root.State, Root.Action>) async {
        await store.send(.home(.buyTapped))
        await store.send(.reputation(.onAppear))
        await store.receive(\.reputation.delegate.checkBuy)
    }

    private static let resume = ReclaimReturnLink.ResumeArgs(sessionID: "session-123", platformID: "GitHub", currencyCode: "BRL")
    private enum Failure: Error { case network }

    private func makeStore(
        checkpoint: OnrampCheckpointModel? = nil,
        extra: (inout DependencyValues) -> Void = { _ in },
        summary: @escaping @Sendable (String) async throws -> ReputationSummaryModel
    ) -> TestStore<Root.State, Root.Action> {
        withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = Root.State.initial
            state.offrampState.selectedCurrencyCode = "BRL"
            let store = TestStore(initialState: state) {
                CombineReducers {
                    Scope<Root.State, Root.Action, Reputation>(state: \.reputationState, action: \.reputation) { Reputation() }
                    Scope<Root.State, Root.Action, IncreaseReputation>(state: \.increaseReputationState, action: \.increaseReputation) {
                        IncreaseReputation()
                    }
                    Scope<Root.State, Root.Action, Onramp>(state: \.onrampState, action: \.onramp) { Onramp() }
                    Root().coordinatorReduce()
                }
            } withDependencies: {
                $0.reputation.summary = summary
                $0.onramp.isConfigured = { true }
                $0.onramp.checkpoint = { checkpoint }
                $0.uuid = .incrementing
                extra(&$0)
            }
            store.exhaustivity = .off
            return store
        }
    }
}
