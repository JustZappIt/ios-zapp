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
                        // Filter first so unrelated events cannot displace transaction updates.
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
                        // A failed fetch must never be silent: a wallet whose every row failed to
                        // decode (field, 2026-08-04 — NULL trust_status meeting a strict decode)
                        // rendered as an EMPTY transaction list with no trace anywhere, reading as
                        // data loss. The list keeps its previous contents; the error goes to the
                        // log where the next investigation can find it.
                        LoggerProxy.error("[RootTransactions] getAllTransactions FAILED — \(error.toZcashError())")
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

                // ZIP 318 labels: Activity now PRESENTS migration transactions instead of hiding
                // them — a stored-but-unmined row renders as "Migrating…"/"Splitting Balance…"
                // with the coins-swap glyph (Figma "Transaction Statuses/Labels — Final Designs"),
                // so the store-at-prove rows that once looked like phantom "Sending…" sends now
                // tell the true in-flight story right on the list. This supersedes the M3 Part A
                // filter that removed them. This is still the single canonical list build, so
                // every consumer of the shared `$transactions` sees the same truth.
                //
                // M3 B2 (unchanged): the SAME rows are what the SDK's pending-balance lanes count
                // for the whole prove→mine window, so their received value is still published
                // beside the canonical list — one pass, one clock — for the balance-breakdown
                // sheet to remove from its displayed "Pending" row. `totalReceived` is exactly a
                // migration transaction's contribution to the pending lanes (all its real outputs
                // are internal, and its spent side never enters them); a nil reads as zero, which
                // under-corrects — conservative, never future-tense.
                let unminedMigrationPending = transactions
                    .filter { $0.isUnminedMigrationTransaction }
                    .reduce(Zatoshi.zero) { $0 + ($1.totalReceived ?? Zatoshi.zero) }
                state.$unminedMigrationPendingValue.withLock { $0 = unminedMigrationPending }

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

                // Re-read pending Zcash transactions in case a push signal was lost. Swap status is
                // provider-owned, so the local SDK database cannot resolve it.
                let pendingTransactionsPoller: Effect<Root.Action>
                if identifiedArray.contains(where: { $0.type == .zcash && $0.isPending }) {
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
