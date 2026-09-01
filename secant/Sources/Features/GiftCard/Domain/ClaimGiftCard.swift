// SPDX-License-Identifier: MIT OR Apache-2.0

@preconcurrency import Combine
import ComposableArchitecture
import Foundation
@preconcurrency import ZcashLightClientKit

/// A link checked as far as it can be without touching the network — which is everything the card
/// says about itself. What it costs to claim needs the chain tip, so that is `birthdayVerdict`,
/// asked for separately: a recipient must see what they were sent while the wallet is still
/// finding the chain, not a spinner.
struct GiftClaimPreview: Equatable {
    let payload: GiftLinkPayload
    /// Derived from the link's mnemonic; the link itself does not carry it.
    let cardAddress: String
    /// False when this device has no wallet yet, so there is nowhere to claim into.
    let hasWallet: Bool
    /// Set when this wallet's own receipt already answers the link — either it holds this card's
    /// funds, or a previous scan proved another holder emptied it. Either way this is the answer
    /// to a link opened twice, and one no amount of scanning can improve on.
    var collected: GiftClaimOutcome?
    /// The transactions of a claim this wallet has already broadcast and that has not reached
    /// finality yet.
    ///
    /// Neither "claimed" nor "unclaimed": the money is on its way and the only thing left is
    /// confirmations, which a rescan cannot hurry. Without this the link opened during that
    /// window answers as an untouched card and offers to claim it all over again.
    var inFlightClaimTxids: [String] = []
}

/// The wallet does not yet know the chain tip, so how far back this card sits cannot be judged.
///
/// Distinct from `GiftLinkError.birthdayAboveTip` on purpose: that means the *card* is wrong, this
/// means *we* are not ready. A wait to be retried, never a verdict on the gift.
struct GiftClaimNotReady: Error, Equatable {}

/// Receipt state could not be read, so absence cannot be asserted safely.
struct GiftReceiptStoreUnreadable: Error, Equatable {}

/// Turns a gift link into money in this wallet.
///
/// Split so that everything checkable offline happens in `preview`, before a single block is
/// downloaded — a tampered or wrong-network link must never get as far as starting a scan, and the
/// recipient must be able to see what a card is worth before deciding whether to scan for it.
struct ClaimGiftCard {
    /// Long enough for a cold-start connection, short enough not to look frozen.
    private static let tipTimeout: Duration = .seconds(30)

    @Dependency(\.date) var date
    @Dependency(\.giftClaim) var giftClaim
    @Dependency(\.giftClaimOperationLock) var giftClaimOperationLock
    @Dependency(\.giftKey) var giftKey
    @Dependency(\.receivedGiftStorage) var receivedGiftStorage
    @Dependency(\.sdkSynchronizer) var sdkSynchronizer
    @Dependency(\.walletStorage) var walletStorage
    @Dependency(\.zcashSDKEnvironment) var zcashSDKEnvironment

    /// Parses and validates the link. Touches neither the network nor the chain, so it returns as
    /// fast as the link can be decoded and the card can go on screen straight away.
    ///
    /// - Throws: `GiftLinkError` with the specific check that failed;
    ///   `GiftReceiptStoreUnreadable` when the receipt store will not read — absence cannot be
    ///   asserted from a store that will not read.
    func preview(_ uri: String) async throws -> GiftClaimPreview {
        // The network is a build flavor on iOS, readable before onboarding — a gift link must be
        // judged on a device with no wallet.
        let networkType = zcashSDKEnvironment.network().networkType
        let payload = try GiftLinkCodec.decode(uri, walletNetwork: networkType)

        // The card's address, which identifies it everywhere below: the isolated wallet's alias
        // and the receipt. Derived rather than carried, so there is nothing to disagree with.
        let cardAddress = try giftKey.deriveAddress(payload.mnemonic, networkType)

        // Never *wait* for a wallet here — a first-launch recipient has none and the preview must
        // render regardless.
        let hasWallet = (try? walletStorage.areKeysPresent()) ?? false

        // Answered from the receipt, before a block is fetched. A card is emptied exactly once,
        // so the record is authoritative for a link opened twice.
        let receipt: ReceivedGift?
        do {
            receipt = try await receivedGiftStorage.getAll()
                .first { $0.address == cardAddress && $0.network == payload.network }
        } catch {
            throw GiftReceiptStoreUnreadable()
        }

        var preview = GiftClaimPreview(payload: payload, cardAddress: cardAddress, hasWallet: hasWallet)
        preview.collected = receipt?.settledOutcome
        if preview.collected == nil, let receipt, !receipt.isSettled, !receipt.claimTxids.isEmpty {
            preview.inFlightClaimTxids = receipt.claimTxids
        }
        return preview
    }

    /// What the recipient still has to agree to — a long foreground scan is their decision, not
    /// something to spring on them.
    ///
    /// - Throws: `GiftClaimNotReady` while the chain tip is still unknown. The card is already on
    ///   screen and correct by then, so this is a wait to be retried, never a verdict on the gift.
    func birthdayVerdict(_ payload: GiftLinkPayload) async throws -> GiftBirthdayVerdict {
        // Wait rather than fail: on the cold start a link produces, the tip is zero for a second
        // or two, and a one-shot read would reject every link opened from a chat.
        var tip = sdkSynchronizer.latestState().latestBlockHeight
        if tip <= 0 {
            let found: BlockHeight? = try? await withTimeout(Self.tipTimeout) {
                for await state in sdkSynchronizer.stateStream().values where state.latestBlockHeight > 0 {
                    return state.latestBlockHeight
                }
                return BlockHeight(0)
            }
            tip = found ?? 0
        }
        guard tip > 0 else { throw GiftClaimNotReady() }
        return try GiftLinkCodec.evaluateBirthday(payload.birthdayHeight, chainTip: Int64(tip))
    }

    /// Syncs the card's own wallet and moves its funds here.
    ///
    /// Claims at least the advertised amount and sweeps spendable top-ups to the same destination.
    /// Fee-reserve dust is the only value that may be intentionally abandoned at final cleanup.
    func callAsFunction(
        payload: GiftLinkPayload,
        cardAddress: String,
        onProgress: @escaping @Sendable (GiftClaimProgress) -> Void
    ) async throws -> GiftClaimOutcome {
        try await giftClaimOperationLock.withLock(cardAddress) {
            try await claimLocked(payload: payload, cardAddress: cardAddress, onProgress: onProgress)
        }
    }

    private func claimLocked(
        payload: GiftLinkPayload,
        cardAddress: String,
        onProgress: @escaping @Sendable (GiftClaimProgress) -> Void
    ) async throws -> GiftClaimOutcome {
        // Read before writing. The distinction between our interrupted submission and a second
        // holder's spend exists only in this preexisting record; manufacturing a prepared receipt
        // first would make every outgoing transaction look local.
        let existing = try await existingReceipt(payload: payload, cardAddress: cardAddress)
        if let existing, existing.isSettled, !existing.claimTxids.isEmpty {
            return .claimed(amount: Zatoshi(existing.amountZatoshi), txIds: existing.claimTxids)
        }

        // Once an unsettled receipt names its recipient, retries stay there. Following account
        // selection would make confirmation search the wrong account or split txids across two.
        let recipient: String
        let destinationAccountUuid: String?
        if let pinned = existing?.destinationAddress {
            recipient = pinned
            destinationAccountUuid = existing?.destinationAccountUuid
        } else {
            @Shared(.inMemory(.selectedWalletAccount)) var selectedWalletAccount: WalletAccount?
            guard let account = selectedWalletAccount, let address = account.unifiedAddress else {
                throw GiftClaimNotReady()
            }
            recipient = address
            destinationAccountUuid = account.id.giftStorageKey
        }

        let prepared = try ReceivedGift(
            address: cardAddress,
            network: payload.network,
            amountZatoshi: Int64(payload.amountZatoshi) ?? 0,
            claimedAt: GiftLinkCodec.instantString(from: date.now()),
            destinationAddress: recipient,
            destinationAccountUuid: destinationAccountUuid,
            message: payload.message,
            claimLink: payload
        )
        // The receipt is written before the scan, so one exists for every card this wallet merely
        // looked at; the discard below releases it when the scan creates nothing.
        try await receivedGiftStorage.record(prepared)

        let resumeEvidence = GiftClaimResumeEvidence(
            claimTxIds: Set(existing?.claimTxids ?? []),
            // Old receipts predate the marker, but a recorded txid itself proves submission.
            submissionWasAttempted: existing?.claimSubmissionAttemptedAt != nil
                || existing?.claimTxids.isEmpty == false
        )

        let request = GiftClaimRequest(
            payload: payload,
            cardAddress: cardAddress,
            networkType: zcashSDKEnvironment.network().networkType,
            // The server the user chose for everything else.
            endpoint: zcashSDKEnvironment.endpoint(),
            recipientAddress: recipient,
            resumeEvidence: resumeEvidence,
            onBeforeSubmit: {
                // The irreversible boundary: if this write fails the engine must never enter its
                // shielded create-and-submit section.
                var marked = prepared
                marked.claimTxids = []
                marked.claimSubmissionAttemptedAt = GiftLinkCodec.instantString(from: date.now())
                try await receivedGiftStorage.record(marked)
            },
            onProgress: onProgress
        )

        let outcome: GiftClaimOutcome
        do {
            outcome = try await giftClaim.claim(request)
        } catch is CancellationError {
            // A cancelled scan never reaches a verdict, so the discard below never runs — and an
            // abandoned scan's receipt is otherwise indistinguishable from an interrupted claim
            // forever: it reopens the claim screen on every foreground and blocks every reset. A
            // no-op past the submission marker, so it can never drop recovery material.
            await Task {
                try? await receivedGiftStorage.discardUnstarted(cardAddress)
            }.value
            throw CancellationError()
        }

        await recordOutcome(outcome, payload: payload, cardAddress: cardAddress, prepared: prepared)
        return outcome
    }

    /// Writes down what the claim turned out to be, on a path the caller's cancellation cannot
    /// skip.
    ///
    /// Three outcomes and three different obligations: a foreign final spend is terminal and
    /// retires the link, a broadcast of ours attaches its txids, and a verdict that created
    /// nothing releases the receipt written before the scan.
    private func recordOutcome(
        _ outcome: GiftClaimOutcome,
        payload: GiftLinkPayload,
        cardAddress: String,
        prepared: ReceivedGift
    ) async {
        await Task {
            if case .alreadyClaimed = outcome {
                // The final foreign spend proves this link has no recovery work left — a terminal
                // answer worth keeping, so reopening the link must not rescan.
                try? await giftClaim.cleanupFinalizedClaim(payload.network, cardAddress)
                try? await receivedGiftStorage.markClaimedElsewhere(cardAddress)
                try? await receivedGiftStorage.settle(cardAddress)
                return
            }

            let submittedTxIds: [String]
            switch outcome {
            case .claimed(_, let txIds):
                submittedTxIds = txIds
            case .notBroadcast(let result):
                switch result {
                case .success(let txIds), .failure(let txIds, _, _), .grpcFailure(let txIds, _), .partial(let txIds, _):
                    submittedTxIds = txIds
                }
            default:
                submittedTxIds = []
            }

            if !submittedTxIds.isEmpty {
                let currentAttempt = try? await receivedGiftStorage.getAll()
                    .first { $0.address == cardAddress && $0.network == payload.network }
                var record = prepared
                record.claimTxids = submittedTxIds
                record.claimSubmissionAttemptedAt = currentAttempt?.claimSubmissionAttemptedAt
                    ?? GiftLinkCodec.instantString(from: date.now())
                try? await receivedGiftStorage.record(record)
            } else {
                // The scan reached a verdict and nothing was created. The receipt written before
                // the scan holds no recovery material — only a copy of a link the sender still
                // has — and left behind it reopens this screen on every foreground and refuses
                // every wallet reset, for a gift that was never taken.
                try? await receivedGiftStorage.discardUnstarted(cardAddress)
            }
        }.value
    }

    private func existingReceipt(payload: GiftLinkPayload, cardAddress: String) async throws -> ReceivedGift? {
        do {
            return try await receivedGiftStorage.getAll()
                .first { $0.address == cardAddress && $0.network == payload.network }
        } catch {
            throw GiftReceiptStoreUnreadable()
        }
    }
}

extension ReceivedGift {
    /// The terminal answer this receipt already holds, or nil when it holds none yet.
    ///
    /// A foreign final spend answers whether or not the settle write that follows it landed. Our
    /// own claim answers only once settled: unsettled means the broadcast reached the mempool and
    /// nothing has confirmed it — such a claim can still expire unmined, so calling it collected
    /// retires a retryable claim over funds still sitting on the card.
    var settledOutcome: GiftClaimOutcome? {
        if isClaimedElsewhere { return .alreadyClaimed }
        if isSettled && !claimTxids.isEmpty { return .claimed(amount: Zatoshi(amountZatoshi), txIds: claimTxids) }
        return nil
    }
}
