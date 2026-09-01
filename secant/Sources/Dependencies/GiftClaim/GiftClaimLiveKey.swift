// SPDX-License-Identifier: MIT OR Apache-2.0

@preconcurrency import Combine
import ComposableArchitecture
import CryptoKit
import Foundation
@preconcurrency import ZcashLightClientKit

extension GiftClaimClient: DependencyKey {
    static let liveValue = GiftClaimClient.live()

    static func live() -> Self {
        // The SDK has no in-process alias guard, so this per-alias lock is the only thing
        // preventing two live synchronizers on one card's database. It is internal to the client
        // and distinct from the use-case-level claim lock, which serializes whole operations by
        // card address.
        let locks = KeyedAsyncLock()
        return Self(
            claim: { request in
                let alias = GiftClaimEngine.aliasSuffix(networkName: request.payload.network, cardAddress: request.cardAddress)
                return try await locks.withLock(alias) {
                    try await GiftClaimEngine().claim(request, aliasSuffix: alias)
                }
            },
            inspect: { request in
                let alias = GiftClaimEngine.aliasSuffix(networkName: request.payload.network, cardAddress: request.cardAddress)
                return try await locks.withLock(alias) {
                    try await GiftClaimEngine().inspect(request, aliasSuffix: alias)
                }
            },
            inspectFinalization: { request in
                let alias = GiftClaimEngine.aliasSuffix(networkName: request.payload.network, cardAddress: request.cardAddress)
                return try await locks.withLock(alias) {
                    try await GiftClaimEngine().inspectFinalization(request, aliasSuffix: alias)
                }
            },
            cleanupFinalizedClaim: { networkName, cardAddress in
                let alias = GiftClaimEngine.aliasSuffix(networkName: networkName, cardAddress: cardAddress)
                try await locks.withLock(alias) {
                    try GiftClaimEngine().deleteWallet(aliasSuffix: alias)
                }
            }
        )
    }
}

/// Something the engine could not reason about — a prepare that did not open the card's wallet, a
/// card wallet with no account. Fails the operation closed; nothing is deleted.
struct GiftClaimEngineFailure: Error, Equatable {}

private struct GiftClaimEngine {
    /// Names the per-card files inside its directory. The custom alias rewrites every URL's last
    /// path component to `c_<alias>_<name>`, which is harmless — everything stays inside the
    /// per-card directory, and cleanup removes the whole directory.
    private enum Layout {
        static let root = "gift-claims"
        static let fsCache = "fs_cache"
        static let general = "general"
        static let dataDb = "data.db"
        static let tor = "tor"
        static let spendParams = "sapling-spend.params"
        static let outputParams = "sapling-output.params"
    }

    /// Fee-reserve dust is the only value that may be abandoned with a card's wallet.
    private static let maxAbandonedResidual = Zatoshi(10_000)

    /// Generous on purpose: this waits out a *cold* isolated synchronizer creating its database
    /// and connecting from scratch, so a short bound fails claims that would have worked.
    private static let serverTimeout: Duration = .seconds(90)

    private static let teardownTimeout: Duration = .seconds(5)

    @Dependency(\.databaseFiles) var databaseFiles
    @Dependency(\.giftKey) var giftKey
    @Dependency(\.transactionGuard) var transactionGuard
    @Dependency(\.userStoredPreferences) var userStoredPreferences
    @Dependency(\.zcashSDKEnvironment) var zcashSDKEnvironment

    /// A stable per-card alias, so an interrupted claim resumes against the same database rather
    /// than rescanning from the card's birthday. From the **address, not the mnemonic**: the
    /// address already identifies the card, and this becomes a filesystem path component.
    static func aliasSuffix(networkName: String, cardAddress: String) -> String {
        let hash = SHA256.hash(data: Data("\(networkName):\(cardAddress)".utf8))
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        return "gift_\(hex.prefix(48))"
    }

    // MARK: - Claim

    func claim(_ request: GiftClaimRequest, aliasSuffix: String) async throws -> GiftClaimOutcome {
        let synchronizer = try await open(
            payload: request.payload,
            networkType: request.networkType,
            endpoint: request.endpoint,
            aliasSuffix: aliasSuffix
        )
        do {
            let outcome = try await claimFrom(synchronizer, request: request)
            await shutdown(synchronizer)
            return outcome
        } catch {
            await shutdown(synchronizer)
            throw error
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func claimFrom(_ synchronizer: SDKSynchronizer, request: GiftClaimRequest) async throws -> GiftClaimOutcome {
        // Same bound as inspect, and for the same reason: the scan that follows is deliberately
        // unbounded — a legitimate claim runs for minutes and the screen offers Stop — but a
        // server that cannot be reached at all must say so rather than leave a bar that will
        // never move.
        try await awaitReachable(synchronizer)
        try await awaitSynced(synchronizer, onProgress: request.onProgress)

        guard let account = try await synchronizer.listAccounts().first else {
            throw GiftClaimEngineFailure()
        }
        let balances = try await synchronizer.getAccountsBalances()
        guard let balance = balances[account.id] else { throw GiftClaimEngineFailure() }
        guard let rawAmount = Int64(request.payload.amountZatoshi) else { throw GiftClaimEngineFailure() }
        let amount = Zatoshi(rawAmount)

        // Resume a transaction retained by the isolated database instead of double-spending.
        let transactions = try await synchronizer.allTransactions()
        let outgoingClaims = transactions.filter { $0.isFinalClaimSpend(of: amount) || $0.isPendingClaimSpend(of: amount) }
        let finalOutgoingIds = Set(outgoingClaims.filter { $0.state == .confirmed }.map { $0.rawID.toHexStringTxId() })
        let pendingOutgoingIds = Set(outgoingClaims.map { $0.rawID.toHexStringTxId() }).subtracting(finalOutgoingIds)

        var locallySubmittedTxIds = request.resumeEvidence.claimTxIds
        if locallySubmittedTxIds.isEmpty && request.resumeEvidence.submissionWasAttempted {
            // A marker proves only that this process crossed the durable boundary. It does not
            // prove that every later spend of this bearer card was ours: the process can die
            // before transaction creation and another link holder can claim next. In marker-only
            // recovery, the pinned destination is the ownership evidence.
            var recovered: Set<String> = []
            for claimSpend in outgoingClaims {
                let recipients = await synchronizer.getRecipients(for: claimSpend)
                let ours = recipients.contains { recipient in
                    if case .address(let target) = recipient {
                        return target.stringEncoded == request.recipientAddress
                    }
                    return false
                }
                if ours {
                    recovered.insert(claimSpend.rawID.toHexStringTxId())
                }
            }
            locallySubmittedTxIds = recovered
        }

        switch classifyOutgoingGiftClaim(
            finalTxIds: finalOutgoingIds,
            pendingTxIds: pendingOutgoingIds,
            locallySubmittedTxIds: locallySubmittedTxIds
        ) {
        case .alreadyClaimed:
            return .alreadyClaimed
        case .awaitingFinality:
            return .awaitingFunding
        case .none, .resume:
            break
        }

        let resumedClaims = outgoingClaims.filter { locallySubmittedTxIds.contains($0.rawID.toHexStringTxId()) }
        let finalClaims = resumedClaims.filter { $0.state == .confirmed }
        let pendingClaims = resumedClaims.filter {
            $0.isPendingClaimSpend(of: amount)
                || (!finalClaims.isEmpty && $0.isSentTransaction && $0.state == .pending)
        }
        if !pendingClaims.isEmpty {
            return .claimed(amount: amount, txIds: pendingClaims.map { $0.rawID.toHexStringTxId() })
        }
        let available = balance.shieldedSpendableValue
        if !finalClaims.isEmpty && available <= Self.maxAbandonedResidual {
            return .claimed(amount: amount, txIds: finalClaims.map { $0.rawID.toHexStringTxId() })
        }

        if finalClaims.isEmpty,
           let blocked = await unspendable(synchronizer, balance: balance, amount: amount, transactions: transactions) {
            return blocked
        }

        guard let recipient = try? Recipient(request.recipientAddress, network: request.networkType) else {
            throw GiftClaimEngineFailure()
        }
        let requested = finalClaims.isEmpty ? amount : Zatoshi(available.amount - Self.maxAbandonedResidual.amount)
        let initialProposal: Proposal
        do {
            initialProposal = try await synchronizer.proposeTransfer(
                accountUUID: account.id,
                recipient: recipient,
                amount: requested,
                memo: nil
            )
        } catch {
            // Detected by pre-arithmetic, never by error-string matching: the amount is there but
            // the fee cannot be covered on top of it. Waiting does not fix a short card, so this
            // must not schedule the wait-and-recheck path.
            if available >= requested {
                return .underfunded(available: available)
            }
            throw error
        }

        // Spendable top-ups go to the recipient; only fee-reserve dust may be abandoned.
        var proposal = initialProposal
        let sweepAmount = Zatoshi(available.amount - initialProposal.totalFeeRequired().amount)
        if sweepAmount > requested {
            proposal = (try? await synchronizer.proposeTransfer(
                accountUUID: account.id,
                recipient: recipient,
                amount: sweepAmount,
                memo: nil
            )) ?? initialProposal
        }

        // Derived before the irreversible boundary, so a derivation failure aborts cleanly.
        let spendingKey = try giftKey.deriveSpendingKey(request.payload.mnemonic, request.networkType)

        // The receipt marker. A throw here aborts before anything irreversible.
        try await request.onBeforeSubmit()

        // The shielded tail: cancelling between submitting and returning leaves nobody knowing
        // whether the money moved, on a card with no reclaim. The unstructured task never
        // inherits the caller's cancellation.
        let finalTxIds = finalClaims.map { $0.rawID.toHexStringTxId() }
        return try await Task {
            let created: [CreatedTransaction]
            do {
                created = try await synchronizer.broadcaster.createProposedTransactions(
                    proposal: proposal,
                    spendingKey: spendingKey
                )
            } catch {
                if case ZcashError.walletTransEncoderCreateTransactionMissingSaplingParams = error {
                    // The scan already found the money; only the proving parameters are missing.
                    // The receipt keeps its marker and the database stays resumable.
                    throw GiftClaimEngineError.paramsUnavailable
                }
                return GiftClaimOutcome.notBroadcast(
                    result: .failure(txIds: [], code: -1, description: "transaction creation failed")
                )
            }

            let result = try await transactionGuard.withSubmission {
                await SDKSynchronizerClient.submitCreatedTransactions(
                    created,
                    logPrefix: "[GiftClaim]",
                    userStoredPreferences: userStoredPreferences,
                    zcashSDKEnvironment: zcashSDKEnvironment,
                    submit: { createdTransactions, endpoints in
                        await SDKSynchronizerClient.submitTransactionsIndividually(createdTransactions, to: endpoints) { transaction, endpoints in
                            await synchronizer.broadcaster.submit(transaction: transaction, to: endpoints)
                        }
                    }
                )
            }

            switch result {
            case .success(let txIds):
                return GiftClaimOutcome.claimed(amount: amount, txIds: finalTxIds + txIds)
            case .failure, .partial, .grpcFailure:
                // The isolated directory is retained: erasing on a partial broadcast strands
                // funds, and the SDK needs the database for background resubmission.
                return GiftClaimOutcome.notBroadcast(result: result)
            }
        }.value
    }

    /// Why the card cannot be spent right now, or nil when it can.
    ///
    /// "Not yet spendable" is never "empty", and "empty" is never "collected" — telling a
    /// recipient a good card is fake is this screen's worst failure. A card the money never
    /// reached is not a card somebody emptied: the funding may still be in the mempool, since a
    /// sender may share in the ~75 seconds before it mines.
    private func unspendable(
        _ synchronizer: SDKSynchronizer,
        balance: AccountBalance,
        amount: Zatoshi,
        transactions: [ZcashTransaction.Overview]
    ) async -> GiftClaimOutcome? {
        let available = balance.shieldedSpendableValue
        let total = balance.shieldedTotal()
        if available >= amount { return nil }
        if total > .zero {
            // Counted from the earliest *mined incoming* transaction that actually delivered the
            // card amount — the address is public, so a stranger's dust must not anchor the count.
            let mined = transactions
                .filter { $0.minedHeight != nil && !$0.isSentTransaction && $0.absoluteValue >= amount }
                .compactMap(\.minedHeight)
                .min()
            let tip = synchronizer.latestState.latestBlockHeight
            var confirmations: Int?
            if let mined, tip > 0 {
                confirmations = max(0, tip - mined + 1)
            }
            return .notYetSpendable(
                available: available,
                total: total,
                confirmations: confirmations,
                requiredConfirmations: giftRequiredConfirmations
            )
        }
        return .awaitingFunding
    }

    // MARK: - Engine plumbing

    private func open(
        payload: GiftLinkPayload,
        networkType: NetworkType,
        endpoint: LightWalletEndpoint,
        aliasSuffix: String
    ) async throws -> SDKSynchronizer {
        let dir = try cardDirectory(aliasSuffix: aliasSuffix)
        linkParamsIfAvailable(into: dir, aliasSuffix: aliasSuffix, networkType: networkType)

        let initializer = Initializer(
            cacheDbURL: nil,
            fsBlockDbRoot: dir.appendingPathComponent(Layout.fsCache),
            // Never the Documents directory itself: the alias would rewrite it into a stray
            // sibling directory outside the per-card layout.
            generalStorageURL: dir.appendingPathComponent(Layout.general),
            dataDbURL: dir.appendingPathComponent(Layout.dataDb),
            torDirURL: dir.appendingPathComponent(Layout.tor),
            endpoint: endpoint,
            network: ZcashNetworkBuilder.network(for: networkType),
            spendParamsURL: dir.appendingPathComponent(Layout.spendParams),
            outputParamsURL: dir.appendingPathComponent(Layout.outputParams),
            saplingParamsSourceURL: SaplingParamsSourceURL.default,
            // Gift wallets never log; the alias keeps their queue labels and per-alias
            // UserDefaults keys off the main wallet's.
            alias: .custom(aliasSuffix),
            loggingPolicy: .noLogging,
            // Deliberate: a bearer card is already public to the link's holders; a second Tor
            // runtime buys no privacy the link has not given away and costs a full bootstrap.
            isTorEnabled: false,
            isExchangeRateEnabled: false
        )
        let synchronizer = SDKSynchronizer(initializer: initializer)

        var seed = try giftKey.deriveSeed(payload.mnemonic)
        defer {
            for index in seed.indices { seed[index] = 0 }
        }
        // Always the card's own birthday, never nil: nil starts the wallet near the tip and
        // reports every card older than ~100 blocks as empty. The same directory with the same
        // seed opens as existing and resumes against the already-scanned database — that
        // resumability is why the alias is deterministic. A directory holding a *different* seed
        // fails closed inside prepare; "recovering" by deleting would be deleting evidence.
        let result = try await synchronizer.prepare(
            with: seed,
            walletBirthday: BlockHeight(payload.birthdayHeight),
            name: "gift",
            keySource: nil
        )
        guard case .success = result else {
            throw GiftClaimEngineFailure()
        }
        try await synchronizer.start(retry: false)
        return synchronizer
    }

    /// After `start`, await the first state that proves the server is reachable. A freshly
    /// prepared instance surfaces `.error` (disconnected) and `.unprepared` while it boots — still
    /// connecting, not failure.
    private func awaitReachable(_ synchronizer: SDKSynchronizer) async throws {
        do {
            try await withTimeout(Self.serverTimeout) {
                for await state in synchronizer.stateStream.values {
                    switch state.syncStatus {
                    case .syncing, .upToDate:
                        return
                    case .stopped:
                        throw GiftClaimEngineError.stopped
                    case .unprepared, .error:
                        continue
                    }
                }
                throw GiftClaimEngineError.stopped
            }
        } catch is TransactionTimeoutError {
            throw GiftClaimEngineError.unreachable
        }
    }

    /// Collects the state stream until synced, forwarding progress, with the stall watchdog
    /// alongside. There is deliberately no overall deadline — a legitimate claim runs for minutes
    /// and the screen offers Stop instead — but movement is bounded: six idle minutes fails as
    /// stalled.
    private func awaitSynced(
        _ synchronizer: SDKSynchronizer,
        onProgress: @escaping @Sendable (GiftClaimProgress) -> Void
    ) async throws {
        let monitor = GiftScanMonitor()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                var tracker = GiftScanStallTracker(height: await monitor.height, fraction: await monitor.fraction)
                while true {
                    try await Task.sleep(for: .seconds(GiftScanStallTracker.pollIntervalSeconds))
                    if tracker.poll(height: await monitor.height, fraction: await monitor.fraction) {
                        throw GiftClaimEngineError.scanStalled
                    }
                }
            }
            group.addTask {
                for await state in synchronizer.stateStream.values {
                    switch state.syncStatus {
                    case .upToDate:
                        return
                    case .stopped:
                        throw GiftClaimEngineError.stopped
                    case .syncing(let fraction, _):
                        let height = state.fullyScannedHeight
                        await monitor.update(height: height > 0 ? Int64(height) : nil, fraction: fraction)
                        // The SDK reports 0 before measuring anything, and a bar pinned at 0%
                        // reads as broken where a sweep reads as working — the screen treats a
                        // zero fraction as indeterminate.
                        onProgress(
                            GiftClaimProgress(
                                fraction: fraction,
                                scannedHeight: height > 0 ? height : nil,
                                tipHeight: state.latestBlockHeight > 0 ? state.latestBlockHeight : nil
                            )
                        )
                    case .unprepared, .error:
                        break
                    }
                }
                throw GiftClaimEngineError.stopped
            }
            do {
                try await group.next()
                group.cancelAll()
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    /// `stop()` is fire-and-forget and teardown finishes later; deleting files under a live
    /// engine races the WAL checkpoint, so wait — bounded — for the stream to report it stopped.
    private func shutdown(_ synchronizer: SDKSynchronizer) async {
        await Task {
            synchronizer.stop()
            try? await withTimeout(Self.teardownTimeout) {
                for await state in synchronizer.stateStream.values {
                    switch state.syncStatus {
                    case .stopped, .unprepared:
                        return
                    default:
                        continue
                    }
                }
            }
        }.value
    }

}

// MARK: - Inspect

extension GiftClaimEngine {
    // MARK: - Inspect

    func inspect(_ request: GiftInspectRequest, aliasSuffix: String) async throws -> GiftCardHoldings {
        let synchronizer = try await open(
            payload: request.payload,
            networkType: request.networkType,
            endpoint: request.endpoint,
            aliasSuffix: aliasSuffix
        )
        let holdings: GiftCardHoldings
        do {
            try await awaitReachable(synchronizer)
            try await awaitSynced(synchronizer, onProgress: request.onProgress)
            holdings = try await readHoldings(synchronizer, payload: request.payload, fundingTxid: request.fundingTxid)
            await shutdown(synchronizer)
        } catch {
            await shutdown(synchronizer)
            throw error
        }
        if holdings.isCollected && holdings.isEmpty {
            try? deleteWallet(aliasSuffix: aliasSuffix)
        }
        return holdings
    }

    func inspectFinalization(_ request: GiftFinalizeInspectRequest, aliasSuffix: String) async throws -> GiftClaimFinalization {
        let synchronizer = try await open(
            payload: request.payload,
            networkType: request.networkType,
            endpoint: request.endpoint,
            aliasSuffix: aliasSuffix
        )
        do {
            try await awaitReachable(synchronizer)
            try await awaitSynced(synchronizer, onProgress: { _ in })
            guard let account = try await synchronizer.listAccounts().first else {
                throw GiftClaimEngineFailure()
            }
            let balances = try await synchronizer.getAccountsBalances()
            guard let balance = balances[account.id] else { throw GiftClaimEngineFailure() }
            guard let rawAmount = Int64(request.payload.amountZatoshi) else { throw GiftClaimEngineFailure() }
            let residual = balance.shieldedTotal()
            let transactions = try await synchronizer.allTransactions()
            let hasFinalSpend = transactions.contains { $0.isFinalClaimSpend(of: Zatoshi(rawAmount)) }
            await shutdown(synchronizer)
            return GiftClaimFinalization(
                canSettle: hasFinalSpend && residual <= Self.maxAbandonedResidual,
                residual: residual
            )
        } catch {
            await shutdown(synchronizer)
            throw error
        }
    }

    private func readHoldings(
        _ synchronizer: SDKSynchronizer,
        payload: GiftLinkPayload,
        fundingTxid: String
    ) async throws -> GiftCardHoldings {
        guard let account = try await synchronizer.listAccounts().first else {
            throw GiftClaimEngineFailure()
        }
        let balances = try await synchronizer.getAccountsBalances()
        guard let balance = balances[account.id] else { throw GiftClaimEngineFailure() }
        guard let rawAmount = Int64(payload.amountZatoshi) else { throw GiftClaimEngineFailure() }
        let amount = Zatoshi(rawAmount)
        let transactions = try await synchronizer.allTransactions()
        return GiftCardHoldings(
            available: balance.shieldedSpendableValue,
            total: balance.shieldedTotal(),
            hasFundingArrived: transactions.contains {
                $0.minedHeight != nil && $0.rawID.toHexStringTxId() == fundingTxid
            },
            hasFinalClaimSpend: transactions.contains { $0.isFinalClaimSpend(of: amount) },
            hasPendingClaimSpend: transactions.contains { $0.isPendingClaimSpend(of: amount) }
        )
    }

}

// MARK: - Files

extension GiftClaimEngine {
    private func giftClaimsRoot() throws -> URL {
        let root = databaseFiles.documentsDirectory().appendingPathComponent(Layout.root)
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: root.path) {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        }
        // Bearer seed material at rest: the SDK excludes its own submit-plan store the same way.
        var url = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return root
    }

    private func cardDirectory(aliasSuffix: String) throws -> URL {
        let dir = try giftClaimsRoot().appendingPathComponent(aliasSuffix)
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Removing the whole directory also catches the `-wal`/`-shm` siblings and the Tor directory
    /// that the SDK's own wipe leaves behind. Throws when something survives — the caller must not
    /// settle a receipt whose database is still on disk.
    func deleteWallet(aliasSuffix: String) throws {
        let dir = try giftClaimsRoot().appendingPathComponent(aliasSuffix)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: dir.path) else { return }
        try fileManager.removeItem(at: dir)
    }

    /// Hard-links (falls back to copying) the main wallet's Sapling params into the per-card
    /// directory at the alias-rewritten names. Best-effort: absent params still scan — only a
    /// spend needs them, and that failure maps to `paramsUnavailable`.
    private func linkParamsIfAvailable(into dir: URL, aliasSuffix: String, networkType: NetworkType) {
        let fileManager = FileManager.default
        let network = ZcashNetworkBuilder.network(for: networkType)
        let pairs = [
            (
                databaseFiles.spendParamsURLFor(network),
                Self.aliasRewritten(dir.appendingPathComponent(Layout.spendParams), aliasSuffix: aliasSuffix)
            ),
            (
                databaseFiles.outputParamsURLFor(network),
                Self.aliasRewritten(dir.appendingPathComponent(Layout.outputParams), aliasSuffix: aliasSuffix)
            )
        ]
        for (source, target) in pairs {
            guard fileManager.fileExists(atPath: source.path), !fileManager.fileExists(atPath: target.path) else { continue }
            do {
                try fileManager.linkItem(at: source, to: target)
            } catch {
                try? fileManager.copyItem(at: source, to: target)
            }
        }
    }

    /// The SDK rewrites every URL's last path component for a custom alias; the params must sit at
    /// the rewritten names the encoder will actually check.
    private static func aliasRewritten(_ url: URL, aliasSuffix: String) -> URL {
        url.deletingLastPathComponent().appendingPathComponent("c_\(aliasSuffix)_\(url.lastPathComponent)")
    }
}

/// Latest scan movement, shared between the state collector and the stall watchdog.
private actor GiftScanMonitor {
    private(set) var height: Int64?
    private(set) var fraction: Float = 0

    func update(height: Int64?, fraction: Float) {
        if let height { self.height = height }
        // Latest, not furthest: the tracker itself keeps furthest-ever, and a regressing height
        // must reach it as-is so a restarting batch is not misread as progress.
        self.fraction = fraction
    }
}
