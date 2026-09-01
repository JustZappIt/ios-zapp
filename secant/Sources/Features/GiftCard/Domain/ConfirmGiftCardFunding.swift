// SPDX-License-Identifier: MIT OR Apache-2.0

@preconcurrency import Combine
import ComposableArchitecture
import Foundation
@preconcurrency import ZcashLightClientKit

struct GiftFundingWatch: Equatable {
    let cardId: String
    let fundingTxid: String
}

/// Reconciles each locally-created card with the main wallet's authoritative transaction database.
///
/// A retry is enabled only from terminal evidence: either the fully-synced database contains no
/// transaction created after the durable start marker, or every candidate belonging to the attempt
/// is expired. Pending and temporarily unavailable data remain unresolved.
///
/// Reads go through the gift custody readers, never the app's display model: `TransactionState`
/// calls a sent transaction non-pending the moment it has a mined height, and a card marked funded
/// off that reading is one a reorg can empty after the sender has been told it holds money.
struct ConfirmGiftCardFunding {
    @Dependency(\.date) var date
    @Dependency(\.giftCardStorage) var giftCardStorage
    @Dependency(\.giftFundingOperationLock) var giftFundingOperationLock
    @Dependency(\.mainQueue) var mainQueue
    @Dependency(\.sdkSynchronizer) var sdkSynchronizer

    /// One send from the card's source account to the card's address, as SDK state.
    private struct SendCandidate {
        let txid: String
        let state: ZcashTransaction.Overview.State?
    }

    /// Waits for one known funding transaction to become either confirmed or safely retryable.
    func callAsFunction(cardId: String, fundingTxid: String) async {
        guard let card = try? await giftCardStorage.get(cardId) else { return }
        let accountKey = card.sourceAccountUuid

        var terminal = await fetchState(of: fundingTxid, accountKey: accountKey)
        if terminal == nil || terminal == .pending {
            let ticks = sdkSynchronizer.stateStream()
                .throttle(for: .seconds(0.2), scheduler: mainQueue, latest: true)
                .values
            for await _ in ticks {
                if Task.isCancelled { return }
                let state = await fetchState(of: fundingTxid, accountKey: accountKey)
                if let state, state != .pending {
                    terminal = state
                    break
                }
            }
        }
        guard let terminal, terminal != .pending else { return }

        try? await giftFundingOperationLock.withLock(cardId) {
            guard
                let current = try? await giftCardStorage.get(cardId),
                current.needsFundingReconciliation,
                current.fundingTxid == fundingTxid
            else { return }
            switch terminal {
            case .confirmed:
                await markFunded(cardId, fundingTxid)
            case .expired:
                // The stream may emit stale state during startup. Re-read from a fully-synced
                // snapshot before allowing another spend; `expired` there is terminal.
                await awaitSynced()
                if let candidates = await sendCandidates(to: current.address, accountKey: accountKey) {
                    await reconcileKnownTransaction(current, txid: fundingTxid, candidates: candidates)
                }
            case .pending:
                break
            }
        }
    }

    /// Recovers every active attempt after process death.
    ///
    /// The per-card operation lock is shared with `FundGiftCard`. It prevents a synced empty
    /// snapshot from clearing the durable marker while transaction creation is still running in
    /// this process. After process death there is no creator left, so a synced absence is
    /// conclusive.
    func reconcile() async -> [GiftFundingWatch] {
        var watches: [GiftFundingWatch] = []
        let cards = (try? await giftCardStorage.getAll()) ?? []
        for snapshot in cards where snapshot.needsFundingReconciliation {
            let watch: GiftFundingWatch? = try? await giftFundingOperationLock.withLock(snapshot.id) {
                guard
                    let card = try? await giftCardStorage.get(snapshot.id),
                    card.needsFundingReconciliation
                else { return nil }
                await awaitSynced()
                guard let candidates = await sendCandidates(to: card.address, accountKey: card.sourceAccountUuid) else {
                    return nil
                }
                await reconcile(card, candidates: candidates)
                guard
                    let after = try? await giftCardStorage.get(card.id),
                    after.needsFundingReconciliation,
                    let txid = after.fundingTxid
                else { return nil }
                return GiftFundingWatch(cardId: card.id, fundingTxid: txid)
            } ?? nil
            if let watch, !watches.contains(watch) {
                watches.append(watch)
            }
        }
        return watches
    }

    /// Reconciles startup state, then keeps every recovered transaction observed for as long as
    /// the calling effect lives. Without this second phase, a transaction first seen pending would
    /// remain stuck until the next screen entry even after it later confirmed or expired.
    func reconcileAndObserve() async {
        let watches = await reconcile()
        guard !watches.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for watch in watches {
                group.addTask {
                    await self(cardId: watch.cardId, fundingTxid: watch.fundingTxid)
                }
            }
        }
    }

    private func reconcile(_ card: StoredGiftCard, candidates: [SendCandidate]) async {
        if let txid = card.fundingTxid {
            await reconcileKnownTransaction(card, txid: txid, candidates: candidates)
        } else {
            await reconcileAttemptWithoutTxid(card, candidates: candidates)
        }
    }

    private func reconcileAttemptWithoutTxid(_ card: StoredGiftCard, candidates: [SendCandidate]) async {
        let historical = Set(card.fundingFailures.compactMap(\.transactionId))
        let owned = candidates.filter { !historical.contains($0.txid) }
        let live = owned.filter { $0.state != .expired }
        // One proposal produces one transaction. More than one live candidate is corrupted or
        // externally-created evidence; choosing either could hide a second spend, so fail closed.
        if live.count > 1 { return }
        if let transaction = live.first {
            await attach(card.id, transaction.txid)
            if transaction.state == .confirmed {
                await markFunded(card.id, transaction.txid)
            }
            return
        }

        let expired = Set(owned.filter { $0.state == .expired }.map(\.txid))
        if !expired.isEmpty {
            await markExpired(card.id, expired)
        } else {
            await markNotCreated(card.id)
        }
    }

    private func reconcileKnownTransaction(_ card: StoredGiftCard, txid: String, candidates: [SendCandidate]) async {
        guard let current = candidates.first(where: { $0.txid == txid }) else { return }
        switch current.state {
        case .confirmed:
            await markFunded(card.id, txid)
        case .expired:
            await reconcileExpiredCurrent(card, currentTxid: txid, candidates: candidates)
        case .pending, .none:
            break
        }
    }

    private func reconcileExpiredCurrent(_ card: StoredGiftCard, currentTxid: String, candidates: [SendCandidate]) async {
        let historical = Set(card.fundingFailures.compactMap(\.transactionId))
        let others = candidates.filter { $0.txid != currentTxid && !historical.contains($0.txid) }
        let live = others.filter { $0.state != .expired }
        if live.count > 1 { return }
        var expired = Set(others.filter { $0.state == .expired }.map(\.txid))
        expired.insert(currentTxid)

        guard let replacement = live.first else {
            await markExpired(card.id, expired)
            return
        }

        // Crash recovery for a process death between SDK creation and recording the new txid:
        // archive the expired evidence and attach the one still-live transaction atomically.
        try? await giftCardStorage.replaceExpiredFunding(
            card.id,
            expired,
            replacement.txid,
            GiftLinkCodec.instantString(from: date.now())
        )
        if replacement.state == .confirmed {
            await markFunded(card.id, replacement.txid)
        }
    }

    /// The SDK-state truth for one txid in the card's source account, or nil while unknown.
    private func fetchState(of txid: String, accountKey: String) async -> ZcashTransaction.Overview.State? {
        guard let overviews = try? await sdkSynchronizer.getTransactionOverviews() else { return nil }
        return overviews.first {
            $0.rawID.toHexStringTxId() == txid && $0.isSentTransaction && $0.accountUUID.giftStorageKey == accountKey
        }?.state
    }

    /// Every send from the account to the card's address, from a snapshot the caller has already
    /// gated on `.upToDate`. Nil when the overviews cannot be read — unresolved, never "absent".
    private func sendCandidates(to address: String, accountKey: String) async -> [SendCandidate]? {
        guard let overviews = try? await sdkSynchronizer.getTransactionOverviews() else { return nil }
        var candidates: [SendCandidate] = []
        for overview in overviews
        where overview.accountUUID.giftStorageKey == accountKey && overview.isSentTransaction {
            let recipients = await sdkSynchronizer.getOverviewRecipients(overview)
            let sendsToCard = recipients.contains { recipient in
                if case .address(let target) = recipient {
                    return target.stringEncoded == address
                }
                return false
            }
            if sendsToCard {
                candidates.append(SendCandidate(txid: overview.rawID.toHexStringTxId(), state: overview.state))
            }
        }
        return candidates
    }

    private func awaitSynced() async {
        if sdkSynchronizer.latestState().syncStatus == .upToDate { return }
        for await state in sdkSynchronizer.stateStream().values where state.syncStatus == .upToDate {
            return
        }
    }

    private func attach(_ cardId: String, _ fundingTxid: String) async {
        try? await giftCardStorage.recordFundingCreated(cardId, fundingTxid, GiftLinkCodec.instantString(from: date.now()))
    }

    private func markNotCreated(_ cardId: String) async {
        try? await giftCardStorage.markFundingNotCreated(cardId, GiftLinkCodec.instantString(from: date.now()))
    }

    private func markExpired(_ cardId: String, _ fundingTxids: Set<String>) async {
        try? await giftCardStorage.markFundingExpired(cardId, fundingTxids, GiftLinkCodec.instantString(from: date.now()))
    }

    private func markFunded(_ cardId: String, _ fundingTxid: String) async {
        try? await giftCardStorage.markFunded(cardId, fundingTxid, GiftLinkCodec.instantString(from: date.now()))
    }
}

extension StoredGiftCard {
    /// Scoped by `isFundingMined`, never by status: a status-scoped sweep skips exactly the cards
    /// shared during the submit-to-mine window.
    var needsFundingReconciliation: Bool {
        guard !isFundingMined else { return false }
        switch fundingLifecycle {
        case .attempting, .created, .submitted:
            return true
        case .neverStarted, .retryable, .mined:
            return false
        }
    }
}
