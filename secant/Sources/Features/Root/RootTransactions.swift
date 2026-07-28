//
//  RootTransactions.swift
//  Zashi
//
//  Created by Lukáš Korba on 29.01.2025.
//

@preconcurrency import Combine
import ComposableArchitecture
import Foundation
@preconcurrency import ZcashLightClientKit

extension Root {
    func transactionsReduce() -> Reduce<Root.State, Root.Action> {
        Reduce { state, action in
            switch action {
            case .observeTransactions:
                return .merge(
                    .publisher {
                        // The transaction events must be filtered out of the stream BEFORE throttling.
                        // Throttling the raw stream with `latest: true` lets an unrelated event
                        // (`.connectionStateChanged`, `.storedUTXOs`) arriving in the same window
                        // replace a `foundTransactions`/`minedTransaction` as "latest", silently
                        // dropping the only signal that a pending transaction got mined.
                        sdkSynchronizer.eventStream()
                            .compactMap {
                                if case SynchronizerEvent.foundTransactions(let transactions, _) = $0 {
                                    return Root.Action.foundTransactions(transactions)
                                } else if case SynchronizerEvent.minedTransaction(let transaction) = $0 {
                                    return Root.Action.minedTransaction(transaction)
                                }
                                return nil
                            }
                            .throttle(for: .seconds(0.2), scheduler: mainQueue, latest: true)
                    }
                    .cancellable(id: state.CancelEventId, cancelInFlight: true),
                    .publisher {
                        sdkSynchronizer.stateStream()
                            .throttle(for: .seconds(0.2), scheduler: mainQueue, latest: true)
                            .map {
                                if $0.syncStatus == .upToDate {
                                    return Root.Action.fetchTransactionsForTheSelectedAccount
                                }
                                return Root.Action.noChangeInTransactions
                            }
                    }
                    .cancellable(id: state.CancelTransactionsStateId, cancelInFlight: true),
                    .send(.fetchTransactionsForTheSelectedAccount)
                )
                
            case .noChangeInTransactions:
                return .none
                
            case .foundTransactions:
                return .send(.fetchTransactionsForTheSelectedAccount)
                
            case .minedTransaction:
                return .send(.fetchTransactionsForTheSelectedAccount)

            case .fetchTransactionsForTheSelectedAccount:
                guard let accountUUID = state.selectedWalletAccount?.id else {
                    return .none
                }
                // Account switches cancel this id explicitly before starting the new account's
                // fetch. Do not add `cancelInFlight`: sync events can arrive every 0.2 seconds and
                // would continually cancel slower reads before any could finish.
                return .run { send in
                    do {
                        let transactions = try await sdkSynchronizer.getAllTransactions(accountUUID)
                        await send(.fetchedTransactions(accountUUID, transactions))
                    } catch {
                        // No user-facing alert: the pending-transactions poller and the next
                        // synchronizer event both retry this fetch.
                        LoggerProxy.error("getAllTransactions failed: \(error.toZcashError())")
                    }
                }
                .cancellable(id: state.CancelTransactionsFetchId)

            case .fetchedTransactions(let accountUUID, var transactions):
                // `SyncStatus` streams are wallet-wide, so a fetch started for the previous account
                // can finish after a switch. Never reconcile or decorate that stale payload; drop it
                // whole unless its provenance still matches the selected account.
                guard accountUUID == state.selectedWalletAccount?.id else {
                    return .none
                }
                let mempoolHeight = sdkSynchronizer.latestState().latestBlockHeight + 1

                // Resolve Swaps
                let allSwaps = userMetadataProvider.allSwaps()
                
                // Swaps From ZEC and CrossPays
                let swapsFromZecAndCrossPays = allSwaps.filter {
                    $0.fromAsset == SwapConstants.zecAssetIdOnNear
                }
                
                swapsFromZecAndCrossPays.forEach { swap in
                    if let transaction = transactions.filter({ $0.zAddress == swap.depositAddress }).first {
                        transactions[id: transaction.id]?.type = swap.exactInput ? .swapFromZec : .crossPay
                        transactions[id: transaction.id]?.swapStatus = swap.swapStatus
                    }
                }

                // Swaps To ZEC
                let swapsToZec = allSwaps.filter {
                    $0.toAsset == SwapConstants.zecAssetIdOnNear
                }

                var mixedTransactions = transactions

                swapsToZec.forEach { swap in
                    mixedTransactions.append(
                        TransactionState(
                            depositAddress: swap.depositAddress,
                            timestamp: TimeInterval(swap.lastUpdated / 1000),
                            zecAmount: swap.amountOutFormatted.localeString ?? swap.amountOutFormatted,
                            swapStatus: swap.swapStatus
                        )
                    )
                }

                // Sort all transactions
                let sortedTransactions = mixedTransactions
                    .sorted { lhs, rhs in
                        if let lhsTimestamp = lhs.timestamp, let rhsTimestamp = rhs.timestamp {
                            return lhsTimestamp > rhsTimestamp
                        } else {
                            return lhs.transactionListHeight(mempoolHeight) > rhs.transactionListHeight(mempoolHeight)
                        }
                    }
                
                let identifiedArray = IdentifiedArrayOf<TransactionState>(uniqueElements: sortedTransactions)

                // Reconciliation poller: while anything is pending, the list must not depend solely
                // on push signals (a dropped event or a missed `.upToDate` tick would otherwise leave
                // a mined transaction rendered as "Sending…" forever). Re-read the local database
                // every 30 seconds until nothing is pending — a cheap SQLite read, no network.
                // Managed on every completed fetch, including ones whose payload equals the current
                // state, so an unchanged list keeps the poller alive.
                let pendingTransactionsPoller: Effect<Root.Action>
                if identifiedArray.contains(where: \.isPending) {
                    pendingTransactionsPoller = .run { send in
                        while !Task.isCancelled {
                            try await mainQueue.sleep(for: .seconds(30))
                            await send(.fetchTransactionsForTheSelectedAccount)
                        }
                    }
                    .cancellable(id: state.CancelPendingTxPollId, cancelInFlight: true)
                } else {
                    pendingTransactionsPoller = .cancel(id: state.CancelPendingTxPollId)
                }

                // Update transactions
                if state.transactions != identifiedArray {
                    state.$transactions.withLock {
                        $0 = identifiedArray
                    }
                    return .merge(
                        pendingTransactionsPoller,
                        .send(.home(.smartBanner(.evaluatePriority6)))
                    )
                }
                // An identical result is still a completed refetch. Without a shared-state write,
                // the transaction stores receive no publisher update and remain invalidated forever
                // when switching between two empty accounts. Signal only stores actually waiting.
                guard state.homeState.transactionListState.isInvalidated
                    || state.transactionsCoordFlowState.transactionsManagerState.isInvalidated else {
                    return pendingTransactionsPoller
                }
                return .merge(
                    pendingTransactionsPoller,
                    .send(.home(.transactionList(.transactionsUpdated))),
                    .send(.transactionsCoordFlow(.transactionsManager(.transactionsUpdated)))
                )

            default: return .none
            }
        }
    }
}
