//
//  TransactionsManagerUnreadFilterTests.swift
//  zodlTests
//
//  The "Unread" chip in the transaction filters, mirroring Android's `TransactionFilter.UNREAD`
//  (`GetFilteredActivitiesUseCase.isUnread`): only received memos the user has not opened yet.
//

import Testing
import Foundation
import ComposableArchitecture
@testable import zodl_internal
@testable @preconcurrency import ZcashLightClientKit

@Suite(.serialized) struct TransactionsManagerUnreadFilterTests {
    @MainActor @Test func applyingUnreadKeepsOnlyUnreadMemos() async {
        await withDependencies {
            $0.defaultInMemoryStorage = .init()
        } operation: {
            let read = LockIsolated<Set<String>>(["read-memo"])
            let store = makeStore(read: read)

            await store.send(.toggleFilter(.unread))
            #expect(store.state.isUnreadFilterActive)
            #expect(store.state.activeFilters.isEmpty) // nothing applies until Apply

            await store.send(.applyFiltersTapped)
            await store.skipReceivedActions()

            #expect(store.state.activeFilters == [.unread])
            #expect(store.state.filteredTransactionsList.ids == ["unread-memo"])
        }
    }

    @MainActor @Test func openingAnUnreadMemoDropsItFromTheUnreadFilter() async {
        await withDependencies {
            $0.defaultInMemoryStorage = .init()
        } operation: {
            let read = LockIsolated<Set<String>>(["read-memo"])
            let store = makeStore(read: read)

            await store.send(.toggleFilter(.unread))
            await store.send(.applyFiltersTapped)
            await store.skipReceivedActions()
            #expect(store.state.filteredTransactionsList.ids == ["unread-memo"])

            await store.send(.transactionTapped("unread-memo"))
            #expect(read.value.contains("unread-memo"))

            await store.send(.updateTransactionsAccordingToFilters)
            await store.skipReceivedActions()
            #expect(store.state.filteredTransactionsList.isEmpty)
        }
    }

    @MainActor @Test func resetClearsTheUnreadFilter() async {
        await withDependencies {
            $0.defaultInMemoryStorage = .init()
        } operation: {
            let store = makeStore(read: LockIsolated(["read-memo"]))

            await store.send(.toggleFilter(.unread))
            await store.send(.applyFiltersTapped)
            await store.skipReceivedActions()
            #expect(store.state.filteredTransactionsList.count == 1)

            await store.send(.resetFiltersTapped)
            await store.skipReceivedActions()

            #expect(!store.state.isUnreadFilterActive)
            #expect(store.state.filteredTransactionsList.count == 4)
        }
    }

    // MARK: - Helpers

    @MainActor
    private func makeStore(read: LockIsolated<Set<String>>) -> TestStoreOf<TransactionsManager> {
        var state = TransactionsManager.State()
        state.$transactions.withLock {
            $0 = [
                tx(id: "unread-memo", memoCount: 1),
                tx(id: "read-memo", memoCount: 1),
                tx(id: "no-memo", memoCount: 0),
                tx(id: "sent-memo", isSent: true, memoCount: 1)
            ]
        }

        let store = TestStore(initialState: state) {
            TransactionsManager()
        } withDependencies: {
            var client = UserMetadataProviderClient()
            client.isRead = { id, _ in read.value.contains(id) }
            client.readTx = { id in read.withValue { _ = $0.insert(id) } }
            $0.userMetadataProvider = client
        }
        store.exhaustivity = .off
        return store
    }

    private func tx(id: String, isSent: Bool = false, memoCount: Int) -> TransactionState {
        TransactionState(
            memoCount: memoCount,
            fee: Zatoshi(10_000),
            id: id,
            status: isSent ? .paid : .received,
            zecAmount: Zatoshi(100_000_000),
            isSentTransaction: isSent
        )
    }
}
