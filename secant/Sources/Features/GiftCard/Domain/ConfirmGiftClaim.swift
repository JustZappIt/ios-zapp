// SPDX-License-Identifier: MIT OR Apache-2.0

@preconcurrency import Combine
import ComposableArchitecture
import Foundation
@preconcurrency import ZcashLightClientKit

/// Drops a received gift's retained link after SDK finality and isolated-wallet cleanup.
struct ConfirmGiftClaim {
    @Dependency(\.giftClaim) var giftClaim
    @Dependency(\.giftClaimOperationLock) var giftClaimOperationLock
    @Dependency(\.mainQueue) var mainQueue
    @Dependency(\.receivedGiftStorage) var receivedGiftStorage
    @Dependency(\.sdkSynchronizer) var sdkSynchronizer
    @Dependency(\.zcashSDKEnvironment) var zcashSDKEnvironment

    /// Suspends until every transaction in `claimTxids` is final in the destination wallet, then
    /// settles the receipt. Cancelling loses nothing: `reconcile` picks the receipt up on the next
    /// pass.
    func callAsFunction(address: String, claimTxids: [String]) async {
        guard !claimTxids.isEmpty else { return }
        guard let receipt = try? await receivedGiftStorage.getAll().first(where: { $0.address == address }) else {
            return
        }
        let accountKeys = await candidateAccountKeys(for: receipt)
        guard !accountKeys.isEmpty else { return }

        // A claim arrives here as an ordinary incoming transaction, not a send.
        var remaining = Set(claimTxids)
        remaining.subtract(await confirmedIncomingTxids(in: accountKeys, matching: remaining))
        if !remaining.isEmpty {
            let ticks = sdkSynchronizer.stateStream()
                .throttle(for: .seconds(0.2), scheduler: mainQueue, latest: true)
                .values
            for await _ in ticks {
                if Task.isCancelled { return }
                remaining.subtract(await confirmedIncomingTxids(in: accountKeys, matching: remaining))
                if remaining.isEmpty { break }
            }
        }
        guard remaining.isEmpty else { return }
        await finalize(address: address)
    }

    /// Confirmations accrued by the least-confirmed transaction of the recorded claim, or nil
    /// while that cannot be read.
    ///
    /// Nil covers two states this wallet cannot tell apart: the claim is built and broadcast by
    /// the *card's* isolated wallet, so this wallet only learns of it when it mines and gets
    /// scanned — before that there is nothing to count, and a claim that will never mine looks
    /// exactly the same. That is why the screen keeps a way to re-check rather than waiting on
    /// this stream alone.
    ///
    /// Read-only and confined to this wallet's own transactions: nothing here opens the card's
    /// wallet or touches its bearer seed.
    func observeClaimConfirmations(address: String) -> AsyncStream<Int?> {
        AsyncStream { continuation in
            let task = Task {
                let receipt = try? await receivedGiftStorage.getAll().first { $0.address == address }
                let claimTxids = receipt?.claimTxids ?? []
                var accountKeys: [String] = []
                if let receipt {
                    accountKeys = await candidateAccountKeys(for: receipt)
                }
                guard !claimTxids.isEmpty, !accountKeys.isEmpty else {
                    continuation.yield(nil)
                    continuation.finish()
                    return
                }
                continuation.yield(await claimConfirmations(claimTxids: claimTxids, accountKeys: accountKeys))
                let ticks = sdkSynchronizer.stateStream()
                    .throttle(for: .seconds(0.2), scheduler: mainQueue, latest: true)
                    .values
                for await _ in ticks {
                    if Task.isCancelled { break }
                    continuation.yield(await claimConfirmations(claimTxids: claimTxids, accountKeys: accountKeys))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Settles every receipt whose claim is already final in some candidate account.
    func reconcile() async {
        let unsettled = ((try? await receivedGiftStorage.getAll()) ?? []).filter { !$0.isSettled }
        guard !unsettled.isEmpty else { return }
        let allKeys = await allAccountKeys()
        let confirmed = await confirmedIncomingByAccount(allKeys)
        for receipt in unsettled where !receipt.claimTxids.isEmpty {
            let candidates = candidateAccountKeys(for: receipt, allKeys: allKeys)
            let settled = candidates.contains { key in
                confirmed[key]?.isSuperset(of: Set(receipt.claimTxids)) == true
            }
            if settled {
                await finalize(address: receipt.address)
            }
        }
    }

    private func finalize(address: String) async {
        try? await giftClaimOperationLock.withLock(address) {
            await finalizeLocked(address: address)
        }
    }

    private func finalizeLocked(address: String) async {
        // Reconcile and a foreground retry read independently. The retry can attach a replacement
        // txid while reconcile waits for the lock, so finalizing a stale snapshot could discard
        // the only retry secret before the replacement is final. Re-read under the lock.
        guard
            let receipt = try? await receivedGiftStorage.getAll().first(where: { $0.address == address && !$0.isSettled }),
            let payload = receipt.claimLink
        else { return }

        let hasFinalDestination: Bool
        if receipt.isFinalized {
            hasFinalDestination = true
        } else if receipt.claimTxids.isEmpty {
            hasFinalDestination = false
        } else {
            let accountKeys = await candidateAccountKeys(for: receipt)
            let confirmed = await confirmedIncomingTxids(in: accountKeys, matching: Set(receipt.claimTxids))
            hasFinalDestination = confirmed.isSuperset(of: Set(receipt.claimTxids))
        }
        guard hasFinalDestination else { return }

        // The card's own wallet must also show a final claim spend with at most fee-reserve dust
        // left before the retry secret may be dropped.
        var canSettle = receipt.isFinalized
        if !canSettle {
            let finalization = try? await giftClaim.inspectFinalization(
                GiftFinalizeInspectRequest(
                    payload: payload,
                    cardAddress: receipt.address,
                    networkType: zcashSDKEnvironment.network().networkType,
                    endpoint: zcashSDKEnvironment.endpoint()
                )
            )
            canSettle = finalization?.canSettle == true
        }
        guard canSettle else { return }

        // Order is load-bearing: the durable checkpoint is written before the database is
        // deleted, so a crash between them resumes cleanly; the link drops last.
        if !receipt.isFinalized {
            guard (try? await receivedGiftStorage.markFinalized(receipt.address)) != nil else { return }
        }
        guard (try? await giftClaim.cleanupFinalizedClaim(payload.network, receipt.address)) != nil else { return }
        try? await receivedGiftStorage.settle(receipt.address)
    }

    private func claimConfirmations(claimTxids: [String], accountKeys: [String]) async -> Int? {
        guard let overviews = try? await sdkSynchronizer.getTransactionOverviews() else { return nil }
        let incoming = overviews.filter {
            !$0.isSentTransaction && accountKeys.contains($0.accountUUID.giftStorageKey)
        }
        let tip = sdkSynchronizer.latestState().latestBlockHeight
        guard tip > 0 else { return nil }
        var minConfirmations: Int?
        for txid in claimTxids {
            // One transaction of the claim still unmined means the claim as a whole has no
            // confirmations to report yet.
            guard let mined = incoming.first(where: { $0.rawID.toHexStringTxId() == txid })?.minedHeight else {
                return nil
            }
            let confirmations = max(0, tip - mined + 1)
            minConfirmations = min(minConfirmations ?? confirmations, confirmations)
        }
        return minConfirmations
    }

    private func confirmedIncomingTxids(in accountKeys: [String], matching txids: Set<String>) async -> Set<String> {
        guard !txids.isEmpty, let overviews = try? await sdkSynchronizer.getTransactionOverviews() else { return [] }
        return Set(
            overviews
                .filter {
                    !$0.isSentTransaction
                        && $0.state == .confirmed
                        && accountKeys.contains($0.accountUUID.giftStorageKey)
                        && txids.contains($0.rawID.toHexStringTxId())
                }
                .map { $0.rawID.toHexStringTxId() }
        )
    }

    private func confirmedIncomingByAccount(_ accountKeys: [String]) async -> [String: Set<String>] {
        guard let overviews = try? await sdkSynchronizer.getTransactionOverviews() else { return [:] }
        var result: [String: Set<String>] = [:]
        for overview in overviews where !overview.isSentTransaction && overview.state == .confirmed {
            let key = overview.accountUUID.giftStorageKey
            guard accountKeys.contains(key) else { continue }
            result[key, default: []].insert(overview.rawID.toHexStringTxId())
        }
        return result
    }

    private func candidateAccountKeys(for receipt: ReceivedGift) async -> [String] {
        candidateAccountKeys(for: receipt, allKeys: await allAccountKeys())
    }

    private func candidateAccountKeys(for receipt: ReceivedGift, allKeys: [String]) -> [String] {
        // A re-imported account can have a new SDK UUID. Falling back to every current account
        // keeps the persisted destination hint useful without making it an orphaning key.
        if let pinned = receipt.destinationAccountUuid, allKeys.contains(pinned) {
            return [pinned]
        }
        return allKeys
    }

    private func allAccountKeys() async -> [String] {
        ((try? await sdkSynchronizer.walletAccounts()) ?? []).map(\.id.giftStorageKey)
    }
}
