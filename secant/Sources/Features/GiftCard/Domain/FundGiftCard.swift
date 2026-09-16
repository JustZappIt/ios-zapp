// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
@preconcurrency import ZcashLightClientKit

/// `card` is already persisted when this exists, and `link` already encodes — a record that will
/// not encode is a card nobody could ever claim, and it must be caught while the money is still in
/// the sender's wallet.
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

    /// The sender backed out of signing on the Keystone. Nothing was sent.
    case signingCancelled

    /// The Keystone lane could not produce a signed transaction. Nothing was sent.
    case signingFailed

    /// The card belongs to a Keystone account other than the selected one, and only the selected
    /// account can sign. Nothing was sent.
    case wrongAccountSelected
}

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
    @Dependency(\.keystoneSigning) var keystoneSigning
    @Dependency(\.mnemonic) var mnemonic
    @Dependency(\.sdkSynchronizer) var sdkSynchronizer
    @Dependency(\.walletStorage) var walletStorage
    @Dependency(\.zcashSDKEnvironment) var zcashSDKEnvironment

    /// Pass `existing` for a card the sender minted but backed out of reviewing; without it, every
    /// trip through the review screen strands another unfunded draft. One already carrying a
    /// funding attempt is refused outright.
    func prepare(
        amount: Zatoshi,
        message: String? = nil,
        expiresAt: Date? = nil,
        existing: StoredGiftCard? = nil
    ) async throws -> GiftFundingQuote {
        // The caller's copy is a snapshot held across a screen the sender can leave and come back
        // to. It may have been superseded by a later mint, or — the half that costs money — have
        // picked up a funding attempt since.
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
            // A retry funds the exact same card; changing the value mints a new one, because the
            // amount is what the bearer link promises.
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

        // Encode before any money can move; see `GiftFundingQuote`.
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

    /// The card stays a draft afterwards: `recordFundingSubmitted` claims only that a transaction
    /// exists, not that it mined. Advancing it to funded is `ConfirmGiftCardFunding`'s job.
    ///
    /// The durable start marker divides this method: before it, failures are `proposalFailed`
    /// (or one of the signing refusals); from it onwards — creation and storage writes included —
    /// `submitUncertain`. The SDK's background resubmitter can broadcast a locally-created
    /// transaction before the app explicitly submits it, and can retry one after a server
    /// rejection.
    ///
    /// The signing material is gathered between two holds of the card's lock: a spending key is
    /// derived in microseconds, but a Keystone signature is a device round trip the sender paces,
    /// and reconciliation must not be blocked for that long. A signed PCZT is inert until a
    /// transaction is created from it, so the marker still precedes anything the SDK could
    /// broadcast.
    func submit(_ quote: GiftFundingQuote) async throws -> String {
        let owner = try await giftFundingOperationLock.withLock(quote.card.id) {
            try await reviewedOwner(of: quote)
        }

        let create: @Sendable () async throws -> [CreatedTransaction]
        switch owner.vendor {
        case .zcash:
            let spendingKey = try spendingKey(for: owner)
            create = { try await sdkSynchronizer.createProposedTransactionsWithoutSubmit(quote.proposal, spendingKey) }
        case .keystone:
            let signed: KeystoneSignedPczt
            do {
                signed = try await keystoneSigning.sign(owner.id, quote.proposal)
            } catch let error as KeystoneSigningError {
                throw GiftFundingError(signing: error)
            }
            create = { try await sdkSynchronizer.createTransactionFromPCZTWithoutSubmit(signed.pcztWithProofs, signed.pcztWithSigs) }
        }

        return try await giftFundingOperationLock.withLock(quote.card.id) {
            _ = try await reviewedOwner(of: quote)
            return try await broadcastLocked(quote, create: create)
        }
    }

    /// Re-reads the card under the lock and requires the exact lifecycle class the sender
    /// reviewed: the quote can sit on a review sheet while reconciliation runs.
    private func reviewedOwner(of quote: GiftFundingQuote) async throws -> WalletAccount {
        guard let current = try? await giftCardStorage.get(quote.card.id),
              current.hasSameFundingIdentity(as: quote.card)
        else {
            throw GiftFundingError.submitUncertain
        }
        if current.hasFundingAttempt || current.isFundingRetryable != quote.card.isFundingRetryable {
            throw GiftFundingError.submitUncertain
        }

        // Refuse rather than guess. Falling back to account 0 would sign the funding transaction
        // with a key the proposal was not built against — and the card records which account owns
        // it precisely so a retry cannot drift to another one.
        let accounts: [WalletAccount]
        do {
            accounts = try await sdkSynchronizer.walletAccounts()
        } catch {
            throw GiftFundingError.proposalFailed
        }
        guard let owner = accounts.first(where: { $0.id.giftStorageKey == current.sourceAccountUuid }) else {
            throw GiftFundingError.proposalFailed
        }
        return owner
    }

    /// Cannot create a transaction, so failures here remain safe to retry.
    private func spendingKey(for owner: WalletAccount) throws -> UnifiedSpendingKey {
        do {
            guard let accountIndex = owner.zip32AccountIndex else { throw GiftFundingError.proposalFailed }
            let storedWallet = try walletStorage.exportWallet()
            let seedBytes = try mnemonic.toSeed(storedWallet.seedPhrase.value())
            return try derivationTool.deriveSpendingKey(
                seedBytes,
                accountIndex,
                zcashSDKEnvironment.network().networkType
            )
        } catch {
            throw GiftFundingError.proposalFailed
        }
    }

    private func broadcastLocked(
        _ quote: GiftFundingQuote,
        create: @escaping @Sendable () async throws -> [CreatedTransaction]
    ) async throws -> String {
        // The durable gate, persisted before creation so no crash or storage failure can leave an
        // auto-broadcast transaction behind an "unfunded" card that is later funded again.
        do {
            try await giftCardStorage.setFundingAttemptedAt(quote.card.id, GiftLinkCodec.instantString(from: date.now()))
        } catch {
            throw GiftFundingError.proposalFailed
        }

        // From here the work is shielded from cancellation: a cancelled screen must not abandon a
        // broadcast mid-flight. The unstructured task never inherits the caller's cancellation.
        let cardId = quote.card.id
        return try await Task {
            let created: CreatedTransaction
            do {
                let transactions = try await create()
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

private extension GiftFundingError {
    init(signing error: KeystoneSigningError) {
        switch error {
        case .rejected: self = .signingCancelled
        case .wrongAccount: self = .wrongAccountSelected
        case .failed, .busy: self = .signingFailed
        }
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
