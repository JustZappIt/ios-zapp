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
                        sdkSynchronizer.eventStream()
                            .throttle(for: .seconds(0.2), scheduler: mainQueue, latest: true)
                            .compactMap {
                                if case SynchronizerEvent.foundTransactions(let transactions, _) = $0 {
                                    return Root.Action.foundTransactions(transactions)
                                } else if case SynchronizerEvent.minedTransaction(let transaction) = $0 {
                                    return Root.Action.minedTransaction(transaction)
                                }
                                return nil
                            }
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
                    if let transactions = try? await sdkSynchronizer.getAllTransactions(accountUUID) {
                        await send(.fetchedTransactions(accountUUID, transactions))
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

                // Update transactions
                if state.transactions != identifiedArray {
                    state.$transactions.withLock {
                        $0 = identifiedArray
                    }
                    return .send(.home(.smartBanner(.evaluatePriority6)))
                }
                // An identical result is still a completed refetch. Without a shared-state write,
                // the transaction stores receive no publisher update and remain invalidated forever
                // when switching between two empty accounts. Signal only stores actually waiting.
                guard state.homeState.transactionListState.isInvalidated
                    || state.transactionsCoordFlowState.transactionsManagerState.isInvalidated else {
                    return .none
                }
                return .merge(
                    .send(.home(.transactionList(.transactionsUpdated))),
                    .send(.transactionsCoordFlow(.transactionsManager(.transactionsUpdated)))
                )

            default: return .none
            }
        }
    }
}
