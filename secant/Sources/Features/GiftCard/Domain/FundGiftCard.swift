// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
@preconcurrency import ZcashLightClientKit

/// What funding a card costs, priced against a real proposal. `card` is already persisted when
/// this exists, and `link` already encodes — a record that will not encode is a card nobody could
/// ever claim, and it must be caught while the money is still in the sender's wallet.
///
/// The sender pays `networkFee` *and* `claimFeeReserve` on top of the card amount, so the
/// recipient nets exactly what the card says.
struct GiftFundingQuote: Equatable {
    let card: StoredGiftCard
    let proposal: Proposal
    let claimFeeReserve: Zatoshi
    let networkFee: Zatoshi
    let link: String

    var cardAmount: Zatoshi { Zatoshi(card.amountZatoshi) }

    /// What leaves the sender's balance: the card, the recipient's future claim fee, and this fee.
    var total: Zatoshi { Zatoshi(card.amountZatoshi + claimFeeReserve.amount + networkFee.amount) }
}

/// Why funding could not start or did not finish. Each case is a distinct thing to tell the
/// sender.
enum GiftFundingError: Error, Equatable {
    /// Refused before any money moved.
    case insufficientFunds

    /// The proposal could not be built. Nothing was sent.
    case proposalFailed

    /// The broadcast neither clearly succeeded nor finally failed — a partial submit, a gRPC
    /// failure, a server rejection retained for SDK retry, or a throw mid-submit. Never invite a
    /// blind retry from here: the first attempt may yet mine, and a card funded twice is money
    /// gone twice.
    case submitUncertain
}

/// Moves money onto a minted gift card.
///
/// Split in two on purpose: `prepare` mints, persists and prices without spending, so the review
/// screen can show real numbers, and `submit` is the only call that moves money. The order is
/// load-bearing and must not be collapsed — the keychain record holds the only copy of the
/// ephemeral seed, so funding an address whose record was not yet written burns the funds.
struct FundGiftCard {
    /// What the sender prepays so the recipient's claim costs them nothing.
    ///
    /// ZIP 317 Rev 0: `fee = 5_000 x max(2, logical_actions)`. A claim spends one funding note
    /// into one output with no change, so the fee floors at 10,000 zatoshi. A floor, not a fee
    /// estimate: Rev 1 against NU6.3 would raise it.
    ///
    /// Unlike `GiftFundingQuote.networkFee` this cannot come from a real proposal — at funding
    /// time the card holds no notes, so there is nothing to propose a claim over.
    static let claimFeeReserve = Zatoshi(10_000)

    @Dependency(\.date) var date
    @Dependency(\.derivationTool) var derivationTool
    @Dependency(\.giftCardStorage) var giftCardStorage
    @Dependency(\.giftFundingOperationLock) var giftFundingOperationLock
    @Dependency(\.mnemonic) var mnemonic
    @Dependency(\.sdkSynchronizer) var sdkSynchronizer
    @Dependency(\.walletStorage) var walletStorage
    @Dependency(\.zcashSDKEnvironment) var zcashSDKEnvironment

    /// Mints a card — or re-prices `existing` — and builds its funding proposal.
    ///
    /// Pass `existing` for a card the sender minted but backed out of reviewing; without it, every
    /// trip through the review screen strands another unfunded draft. One already carrying a
    /// funding attempt is refused outright.
    func prepare(
        amount: Zatoshi,
        message: String? = nil,
        expiresAt: Date? = nil,
        existing: StoredGiftCard? = nil
    ) async throws -> GiftFundingQuote {
        // Re-read rather than trust the copy handed in. The caller's is a snapshot held across a
        // screen the sender can leave and come back to, so it can be stale in both directions:
        // the record may have been superseded by a later mint and no longer exist, and — the half
        // that costs money — it may have picked up a funding attempt that this copy does not show.
        var current: StoredGiftCard?
        if let existing {
            current = try await giftCardStorage.get(existing.id)
        }

        // The durable gate on double funding. The screen's error state cannot be it: stepping
        // back to the details and continuing again clears that error and lands here with the same
        // card.
        if current?.hasFundingAttempt == true { throw GiftFundingError.submitUncertain }
        if existing?.isFundingRetryable == true && current?.isFundingRetryable != true {
            // Never turn a disappeared or concurrently-resolved retry into a newly minted card.
            // Its address and link are the point of retrying, and a second card would be a new
            // spend.
            throw GiftFundingError.submitUncertain
        }
        if let current, current.amountZatoshi != amount.amount {
            // Repricing an existing address is never permission to silently change what its
            // bearer link promises. A retry funds the exact same card; changing the value mints a
            // new one.
            throw GiftFundingError.proposalFailed
        }

        let account: WalletAccount
        if let current {
            // A retry belongs to the recorded source account, irrespective of which account is
            // selected now. Otherwise reconciliation would query one wallet for a transaction
            // created in another and could eventually authorize yet another retry.
            let accounts = (try? await sdkSynchronizer.walletAccounts()) ?? []
            guard let owner = accounts.first(where: { $0.id.giftStorageKey == current.sourceAccountUuid }) else {
                throw GiftFundingError.proposalFailed
            }
            account = owner
        } else {
            @Shared(.inMemory(.selectedWalletAccount)) var selectedWalletAccount: WalletAccount?
            guard let selected = selectedWalletAccount else { throw GiftFundingError.proposalFailed }
            account = selected
        }

        guard let fundingAmount = amount.plusWithinRange(Self.claimFeeReserve) else {
            throw GiftFundingError.insufficientFunds
        }

        // Cheap refusal before minting, so an obviously unaffordable card leaves no draft behind.
        // The authoritative check is still the proposal below, which knows about note selection
        // and the fee this particular send needs.
        let spendable = try await spendableBalance(of: account)
        if fundingAmount.amount > spendable.amount { throw GiftFundingError.insufficientFunds }

        // A draft that is gone was superseded by a later mint, so this mints again rather than
        // pricing a record nothing can fund.
        let card: StoredGiftCard
        if let current {
            card = current
        } else {
            card = try await CreateGiftCard()(
                amount: amount,
                message: message,
                expiresAt: expiresAt,
                sourceAccount: account
            )
        }

        let networkType = zcashSDKEnvironment.network().networkType
        guard let recipient = try? Recipient(card.address, network: networkType) else {
            throw GiftFundingError.proposalFailed
        }

        let proposal: Proposal
        do {
            // No memo. A memo would be readable by whoever claims the card and by nobody else,
            // and the sender's message already rides in the link, where it costs no chain space
            // and leaks nothing on-chain.
            proposal = try await sdkSynchronizer.proposeTransfer(account.id, recipient, fundingAmount, nil)
        } catch {
            // The SDK's proposal error carries no structured discriminator, so classify by
            // re-checking spendable-vs-needed rather than by matching error strings.
            let nowSpendable = (try? await spendableBalance(of: account)) ?? spendable
            if fundingAmount.amount > nowSpendable.amount {
                throw GiftFundingError.insufficientFunds
            }
            throw GiftFundingError.proposalFailed
        }

        let networkFee = proposal.totalFeeRequired()
        guard fundingAmount.plusWithinRange(networkFee) != nil else {
            throw GiftFundingError.insufficientFunds
        }

        // Encode before any money can move: a link the codec would refuse to decode is a card
        // whose funds nobody can ever reach.
        guard let link = try? GiftLinkCodec.encode(card.toLinkPayload()) else {
            throw GiftFundingError.proposalFailed
        }

        return GiftFundingQuote(
            card: card,
            proposal: proposal,
            claimFeeReserve: Self.claimFeeReserve,
            networkFee: networkFee,
            link: link
        )
    }

    /// Broadcasts the quote's funding transaction and records the txid against the card.
    ///
    /// The card stays a draft afterwards: `recordFundingSubmitted` claims only that a transaction
    /// exists, not that it mined. Advancing it to funded is `ConfirmGiftCardFunding`'s job, once
    /// there is a block behind it.
    ///
    /// The durable start marker divides this method: before it, failures are `proposalFailed`;
    /// from it onwards — creation and storage writes included — `submitUncertain`. The SDK's
    /// background resubmitter can broadcast a locally-created transaction before the app
    /// explicitly submits it, and can retry one after a server rejection.
    ///
    /// - Returns: the funding txid.
    func submit(_ quote: GiftFundingQuote) async throws -> String {
        try await giftFundingOperationLock.withLock(quote.card.id) {
            try await submitLocked(quote)
        }
    }

    private func submitLocked(_ quote: GiftFundingQuote) async throws -> String {
        // The quote can sit on a review sheet while reconciliation runs. Re-read under the same
        // lock used by reconciliation and require the exact lifecycle class the sender reviewed.
        guard let current = try? await giftCardStorage.get(quote.card.id),
              current.hasSameFundingIdentity(as: quote.card)
        else {
            throw GiftFundingError.submitUncertain
        }
        if current.hasFundingAttempt || current.isFundingRetryable != quote.card.isFundingRetryable {
            throw GiftFundingError.submitUncertain
        }

        // Key lookup happens before the durable boundary and cannot create a transaction, so
        // failures here remain safe to retry.
        let spendingKey: UnifiedSpendingKey
        do {
            let accounts = try await sdkSynchronizer.walletAccounts()
            let owner = accounts.first { $0.id.giftStorageKey == current.sourceAccountUuid }
            let storedWallet = try walletStorage.exportWallet()
            let seedBytes = try mnemonic.toSeed(storedWallet.seedPhrase.value())
            spendingKey = try derivationTool.deriveSpendingKey(
                seedBytes,
                owner?.zip32AccountIndex ?? Zip32AccountIndex(0),
                zcashSDKEnvironment.network().networkType
            )
        } catch {
            throw GiftFundingError.proposalFailed
        }

        // The SDK may resubmit a transaction merely because it exists in the wallet database,
        // even before submit is called. Persist the unresolved gate before creation so no crash
        // or storage failure can leave an auto-broadcast transaction behind an "unfunded" card
        // that is later discarded or funded again.
        do {
            try await giftCardStorage.setFundingAttemptedAt(quote.card.id, GiftLinkCodec.instantString(from: date.now()))
        } catch {
            throw GiftFundingError.proposalFailed
        }

        // From here the work is shielded from cancellation: a cancelled screen must not abandon a
        // broadcast mid-flight. The unstructured task never inherits the caller's cancellation.
        let cardId = quote.card.id
        let proposal = quote.proposal
        return try await Task {
            let created: CreatedTransaction
            do {
                let transactions = try await sdkSynchronizer.createProposedTransactionsWithoutSubmit(proposal, spendingKey)
                guard transactions.count == 1, let single = transactions.first else {
                    throw GiftFundingError.submitUncertain
                }
                created = single
            } catch {
                // Creation is past the durable marker, so a throw here is already uncertain.
                throw GiftFundingError.submitUncertain
            }

            let txid = created.txId.toHexStringTxId()
            do {
                try await giftCardStorage.recordFundingCreated(cardId, txid, GiftLinkCodec.instantString(from: date.now()))
            } catch {
                throw GiftFundingError.submitUncertain
            }

            let result: SDKSynchronizerClient.CreateProposedTransactionsResult
            do {
                result = try await sdkSynchronizer.submitCreatedTransactionsForGift([created])
            } catch {
                throw GiftFundingError.submitUncertain
            }

            switch result {
            case .success(let txIds):
                let submittedTxid = txIds.first ?? txid
                do {
                    // Past the broadcast, so a refusal here loses the record of where the money
                    // went, not the money — and cannot be reported as a funding that never
                    // happened.
                    try await giftCardStorage.recordFundingSubmitted(
                        cardId,
                        submittedTxid,
                        GiftLinkCodec.instantString(from: date.now())
                    )
                } catch {
                    throw GiftFundingError.submitUncertain
                }
                return submittedTxid

            case .failure, .partial, .grpcFailure:
                // None of these makes the locally-created transaction ineligible for automatic
                // SDK resubmission, including an RPC rejection. Clearing its txid here could make
                // a later retry fund a card the app now considers abandoned.
                throw GiftFundingError.submitUncertain
            }
        }.value
    }

    private func spendableBalance(of account: WalletAccount) async throws -> Zatoshi {
        let balances = try await sdkSynchronizer.getAccountsBalances()
        return balances[account.id]?.shieldedSpendableValue ?? .zero
    }
}

private extension StoredGiftCard {
    /// Custody and promise fields that the reviewed proposal is allowed to spend toward.
    func hasSameFundingIdentity(as other: StoredGiftCard) -> Bool {
        var normalized = self
        normalized.status = other.status
        normalized.updatedAt = other.updatedAt
        normalized.lastCheckedAt = other.lastCheckedAt
        return normalized == other
    }
}

extension Zatoshi {
    /// Adds two bounded monetary values without letting `Zatoshi`'s clamping constructor become
    /// control flow.
    func plusWithinRange(_ other: Zatoshi) -> Zatoshi? {
        let sum = amount + other.amount
        guard sum <= Zatoshi.Constants.maxZatoshi else { return nil }
        return Zatoshi(sum)
    }
}
