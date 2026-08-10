//
//  RootPendingTransactionRefreshTests.swift
//  zodlTests
//
//  Covers transaction refresh signals, foreground recovery and pending-state reconciliation.
//

@preconcurrency import Combine
import Foundation
import Testing
import ComposableArchitecture
@testable @preconcurrency import ZcashLightClientKit
@testable import zodl_internal

@Suite(.serialized) @MainActor struct RootPendingTransactionRefreshTests {
    private static func walletAccount(idByte: UInt8) -> WalletAccount {
        WalletAccount(
            Account(
                id: AccountUUID(id: [UInt8](repeating: idByte, count: 16)),
                name: "Zodl",
                keySource: nil,
                seedFingerprint: nil,
                hdAccountIndex: Zip32AccountIndex(0),
                ufvk: nil,
                uivk: nil
            )
        )
    }

    private func tx(id: String, status: TransactionState.Status) -> TransactionState {
        TransactionState(fee: Zatoshi(10), id: id, status: status, zecAmount: Zatoshi(100_000))
    }

    // MARK: - Event Stream

    @Test func foundTransactionsSurvivesUnrelatedEventsInTheSameThrottleWindow() async {
        let account = Self.walletAccount(idByte: 80)
        let scheduler = DispatchQueue.test
        let events = PassthroughSubject<SynchronizerEvent, Never>()
        let fetchCalls = LockIsolated<Int>(0)

        var initialState = Root.State.initial
        initialState.$selectedWalletAccount.withLock { $0 = account }
        initialState.$transactions.withLock { $0 = [] }
        initialState.homeState.transactionListState.isInvalidated = false
        initialState.transactionsCoordFlowState.transactionsManagerState.isInvalidated = false

        let store = Store(initialState: initialState) {
            Root()
        } withDependencies: {
            baseNoOpDependencies(&$0)
            $0.mainQueue = scheduler.eraseToAnyScheduler()
            $0.sdkSynchronizer = .mocked(eventStream: { events.eraseToAnyPublisher() })
            $0.sdkSynchronizer.getAllTransactions = { _ in
                fetchCalls.withValue { $0 += 1 }
                return []
            }
        }

        store.send(.observeTransactions)
        await waitForRootStore { fetchCalls.value >= 1 }

        for _ in 0..<50 where fetchCalls.value < 2 {
            events.send(.connectionStateChanged(.online))
            events.send(.foundTransactions([], nil))
            events.send(.connectionStateChanged(.online))
            await scheduler.advance(by: .seconds(0.5))
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(fetchCalls.value >= 2, "a foundTransactions event sandwiched between unrelated events never triggered a fetch")
    }

    // MARK: - App Lifecycle

    @Test func retryStartAfterBackgroundingReestablishesTransactionObservation() async {
        let account = Self.walletAccount(idByte: 81)
        let scheduler = DispatchQueue.test
        let events = PassthroughSubject<SynchronizerEvent, Never>()
        let fetchCalls = LockIsolated<Int>(0)

        var initialState = Root.State.initial
        initialState.$selectedWalletAccount.withLock { $0 = account }
        initialState.$transactions.withLock { $0 = [] }
        initialState.homeState.transactionListState.isInvalidated = false
        initialState.transactionsCoordFlowState.transactionsManagerState.isInvalidated = false

        let store = Store(initialState: initialState) {
            Root()
        } withDependencies: {
            baseNoOpDependencies(&$0)
            $0.mainQueue = scheduler.eraseToAnyScheduler()
            $0.diskSpaceChecker = .mockEmptyDisk
            $0.sdkSynchronizer = .mocked(
                eventStream: { events.eraseToAnyPublisher() },
                latestState: {
                    var latestState = SynchronizerState.zero
                    latestState.syncStatus = .upToDate
                    return latestState
                }
            )
            $0.sdkSynchronizer.getAllTransactions = { _ in
                fetchCalls.withValue { $0 += 1 }
                return []
            }
        }

        store.send(.observeTransactions)
        await waitForRootStore { fetchCalls.value >= 1 }

        for _ in 0..<50 where fetchCalls.value < 2 {
            events.send(.foundTransactions([], nil))
            await scheduler.advance(by: .seconds(0.5))
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        await waitForRootStore { fetchCalls.value >= 2 }

        store.send(.initialization(.appDelegate(.didEnterBackground)))
        try? await Task.sleep(nanoseconds: 100_000_000)
        let fetchesBeforeBackgroundProbe = fetchCalls.value

        for _ in 0..<5 {
            events.send(.foundTransactions([], nil))
            await scheduler.advance(by: .seconds(0.5))
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(fetchCalls.value == fetchesBeforeBackgroundProbe, "the event subscription survived backgrounding")

        let fetchesBeforeRetryStart = fetchCalls.value
        store.send(.initialization(.retryStart))
        await waitForRootStore { fetchCalls.value >= fetchesBeforeRetryStart + 1 }

        let fetchesBeforeEventProbe = fetchCalls.value
        for _ in 0..<50 where fetchCalls.value < fetchesBeforeEventProbe + 1 {
            events.send(.foundTransactions([], nil))
            await scheduler.advance(by: .seconds(0.5))
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(fetchCalls.value >= fetchesBeforeEventProbe + 1, "no event-driven fetch after foreground retryStart")
    }

    // MARK: - Reconciliation Poller

    @Test func swapPendingAloneDoesNotArmThePoller() async {
        let account = Self.walletAccount(idByte: 83)
        let scheduler = DispatchQueue.test
        let fetchCalls = LockIsolated<Int>(0)

        let pendingSwap = TransactionState(
            depositAddress: "deposit-address",
            timestamp: 1,
            zecAmount: "1",
            swapStatus: .pending
        )
        #expect(pendingSwap.isPending, "fixture must be pending, else the test proves nothing")
        #expect(pendingSwap.type != .zcash)

        var initialState = Root.State.initial
        initialState.$selectedWalletAccount.withLock { $0 = account }
        initialState.$transactions.withLock { $0 = [] }
        initialState.homeState.transactionListState.isInvalidated = false
        initialState.transactionsCoordFlowState.transactionsManagerState.isInvalidated = false

        let store = Store(initialState: initialState) {
            Root()
        } withDependencies: {
            baseNoOpDependencies(&$0)
            $0.mainQueue = scheduler.eraseToAnyScheduler()
            $0.sdkSynchronizer.getAllTransactions = { _ in
                fetchCalls.withValue { $0 += 1 }
                return IdentifiedArrayOf(uniqueElements: [pendingSwap])
            }
        }

        store.send(.fetchedTransactions(account.id, [pendingSwap]))
        try? await Task.sleep(nanoseconds: 100_000_000)

        for _ in 0..<5 {
            await scheduler.advance(by: .seconds(30))
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(fetchCalls.value == 0, "a swap-only pending list must not arm the local-database poller")
    }

    @Test func cancellingThePollerPreventsAnyLaterTick() async {
        let account = Self.walletAccount(idByte: 84)
        let scheduler = DispatchQueue.test
        let fetchCalls = LockIsolated<Int>(0)
        let pendingTransaction = tx(id: "pending-tx", status: .sending)

        var initialState = Root.State.initial
        initialState.$selectedWalletAccount.withLock { $0 = account }
        initialState.$transactions.withLock { $0 = [] }
        initialState.homeState.transactionListState.isInvalidated = false
        initialState.transactionsCoordFlowState.transactionsManagerState.isInvalidated = false

        let store = Store(initialState: initialState) {
            Root()
        } withDependencies: {
            baseNoOpDependencies(&$0)
            $0.mainQueue = scheduler.eraseToAnyScheduler()
            $0.sdkSynchronizer.getAllTransactions = { _ in
                fetchCalls.withValue { $0 += 1 }
                return IdentifiedArrayOf(uniqueElements: [pendingTransaction])
            }
        }

        store.send(.fetchedTransactions(account.id, [pendingTransaction]))
        for _ in 0..<40 where fetchCalls.value < 1 {
            await scheduler.advance(by: .seconds(1))
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(fetchCalls.value >= 1, "poller never armed, so cancellation proves nothing")

        await scheduler.advance(by: .seconds(10))
        store.send(.initialization(.appDelegate(.didEnterBackground)))
        try? await Task.sleep(nanoseconds: 200_000_000)
        let fetchesAtCancellation = fetchCalls.value

        for _ in 0..<5 {
            await scheduler.advance(by: .seconds(30))
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(
            fetchCalls.value == fetchesAtCancellation,
            "a sleep in flight at cancellation still dispatched a fetch afterwards"
        )
    }

    @Test func pollerRefetchesWhilePendingAndStopsWhenResolved() async {
        let account = Self.walletAccount(idByte: 82)
        let scheduler = DispatchQueue.test
        let fetchCalls = LockIsolated<Int>(0)
        let pendingTransaction = tx(id: "pending-tx", status: .sending)

        var initialState = Root.State.initial
        initialState.$selectedWalletAccount.withLock { $0 = account }
        initialState.$transactions.withLock { $0 = [] }
        initialState.homeState.transactionListState.isInvalidated = false
        initialState.transactionsCoordFlowState.transactionsManagerState.isInvalidated = false

        let store = Store(initialState: initialState) {
            Root()
        } withDependencies: {
            baseNoOpDependencies(&$0)
            $0.mainQueue = scheduler.eraseToAnyScheduler()
            $0.sdkSynchronizer.getAllTransactions = { _ in
                fetchCalls.withValue { $0 += 1 }
                return IdentifiedArrayOf(uniqueElements: [pendingTransaction])
            }
        }

        store.send(.fetchedTransactions(account.id, [pendingTransaction]))

        // Small advances allow the effect to register each sleep on the test scheduler.
        for _ in 0..<40 where fetchCalls.value < 1 {
            await scheduler.advance(by: .seconds(1))
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(fetchCalls.value >= 1, "the poller never ticked while a transaction was pending")

        for _ in 0..<40 where fetchCalls.value < 2 {
            await scheduler.advance(by: .seconds(1))
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(fetchCalls.value >= 2, "the poller did not survive an unchanged still-pending fetch result")

        store.send(.fetchedTransactions(account.id, [tx(id: "pending-tx", status: .paid)]))
        try? await Task.sleep(nanoseconds: 100_000_000)
        let fetchesAfterResolution = fetchCalls.value

        for _ in 0..<5 {
            await scheduler.advance(by: .seconds(60))
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(fetchCalls.value == fetchesAfterResolution, "the poller kept ticking after the last pending transaction resolved")
    }
}

@MainActor
private func baseNoOpDependencies(_ values: inout DependencyValues) {
    values.autoServerSelection.findBestServer = { nil }
    values.databaseFiles = .noOp
    values.derivationTool = .liveValue
    values.diskSpaceChecker = .mockFullDisk
    values.flexaHandler = .noOp
    values.localAuthentication = .mockAuthenticationSucceeded
    values.mnemonic = .mock
    values.readTransactionsStorage.resetZashi = { }
    values.sdkSynchronizer = .noOp
    values.userMetadataProvider.allSwaps = { [] }
    values.userMetadataProvider.load = { _ in }
    values.walletStorage = .noOp
    values.zcashSDKEnvironment = .testnet
}

@MainActor
private func waitForRootStore(
    timeoutNanoseconds: UInt64 = 15_000_000_000,
    sourceLocation: SourceLocation = #_sourceLocation,
    condition: @escaping @MainActor () -> Bool
) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while !condition(), DispatchTime.now().uptimeNanoseconds < deadline {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(condition(), "Timed out waiting for Root pending-transaction-refresh store state", sourceLocation: sourceLocation)
}
