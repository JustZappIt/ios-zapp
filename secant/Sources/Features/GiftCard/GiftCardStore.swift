// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
@preconcurrency import ZcashLightClientKit

/// Drives the create-a-gift-card flow: enter an amount, review what it costs, fund it, share it.
///
/// One ordering carries the whole feature. Minting, persisting and encoding the link all happen in
/// prepare, entirely before submit moves any money — a record that will not encode is a card whose
/// funds nobody could ever reach, and there is no reclaim, so it has to be caught while the money
/// is still in the sender's wallet.
@Reducer
struct GiftCard {
    /// Where the sender is in the flow. The order is the order they travel in; `unavailable` is
    /// the fail-closed branch from `ready` when the persisted card is no longer safe to hand out.
    enum Stage: Equatable {
        case details
        case preparing
        case review
        case funding
        case ready
        case unavailable
    }

    /// How long a card suggests it stays claimable. Advisory — nothing on chain enforces it.
    enum Expiry: Int, Equatable, CaseIterable {
        case never = 0
        case week = 7
        case month = 30
        case quarter = 90
    }

    /// Everything the screen can tell the sender went wrong.
    enum FlowError: Equatable {
        case amountInvalid
        case messageTooLong
        case insufficientFunds
        case keystoneUnsupported
        case unsupportedNetwork
        case chainTipUnavailable
        case persistFailed
        case mintFailed
        case proposalFailed
        case authenticationFailed
        /// Broadcast outcome unknown. The copy must not invite a retry.
        case submitUncertain
        case shareFailed
    }

    /// The inputs a draft was minted for. Re-minting on an unchanged set would strand the old
    /// draft; re-using one minted for different inputs would fund the wrong promise.
    struct PreparedInputs: Equatable {
        let amountZatoshi: Int64
        let message: String?
        let expiry: Expiry
    }

    @ObservableState
    struct State: Equatable {
        var stage: Stage = .details
        var amountInput = ""
        var message = ""
        var expiry: Expiry = .never
        var quote: GiftFundingQuote?
        var link: String?
        var preparedFor: PreparedInputs?
        var isAuthenticating = false
        var error: FlowError?
        var hasStoredCards = false
        /// Whether the ready card can still be handed off, re-checked from storage on every
        /// mutation. False flips `ready` to `unavailable` — claimed meanwhile, or store refused.
        var isReadyCardHandable = true
        /// Non-nil presents the share sheet with the full link.
        var shareLink: String?
        var spendableBalanceText: String?
        @Shared(.inMemory(.exchangeRate)) var currencyConversion: CurrencyConversion? = nil

        /// What the sender typed, exactly representable or nil.
        var typedAmount: Zatoshi? {
            GiftAmount.fromZec(Decimal(string: amountInput))?.zatoshi
        }

        /// The figure on the podium: what is typed wins on details — backing out of review keeps
        /// the quote, and preferring it there froze the preview on the old figure while the sender
        /// typed a new one.
        var previewAmount: Zatoshi? {
            visibleStage == .details ? typedAmount : quote?.cardAmount ?? typedAmount
        }

        /// Nil wherever the wallet has no rate — opted out, or not loaded yet. Then no fiat at
        /// all, never a zero: a zero reads as a worthless card.
        var fiatText: String? {
            guard let amount = previewAmount, let conversion = currencyConversion else { return nil }
            let text: String = conversion.convert(amount)
            return text
        }

        var visibleStage: Stage {
            stage == .ready && !isReadyCardHandable ? .unavailable : stage
        }

        var messageGraphemes: Int {
            GiftMessage.graphemeCount(message)
        }

        var isMessageTooLong: Bool {
            !message.isEmpty && !GiftMessage.isWithinLimits(message)
        }

        /// Both message bounds, not just the counter's: a note can sit well under 128 clusters and
        /// still blow the 512-byte limit, and the link codec would refuse to encode it.
        var canContinue: Bool {
            typedAmount != nil && (message.isEmpty || GiftMessage.isWithinLimits(message))
        }

        /// `submitUncertain` latches funding off for good: the note may already be spent, and a
        /// live button invites the retry its copy is asking the sender not to make. The way on is
        /// the saved-cards list.
        var canConfirm: Bool {
            !isAuthenticating && error != .submitUncertain
        }

        /// From details, and from the one review the sender cannot fund their way out of.
        var canOpenSavedCards: Bool {
            guard hasStoredCards else { return false }
            switch visibleStage {
            case .details, .unavailable:
                return true
            case .review:
                return error == .submitUncertain
            case .preparing, .funding, .ready:
                return false
            }
        }

        /// Whether the sender may go back. Preparation and funding are kept on-screen; a funded
        /// card is already durable and re-shareable from the saved-cards list.
        var isBackEnabled: Bool {
            switch visibleStage {
            case .details, .ready, .unavailable:
                return true
            case .review:
                return !isAuthenticating
            case .preparing, .funding:
                return false
            }
        }
    }

    enum Action: BindableAction {
        case authenticationFinished(Bool)
        case backTapped
        case binding(BindingAction<State>)
        case delegate(Delegate)
        case expiryChanged(Expiry)
        case funded(String)
        case fundingFailed(FlowError)
        case fundTapped
        case handOffRefused
        case onAppear
        case openSavedCardsTapped
        case prepared(GiftFundingQuote, PreparedInputs)
        case prepareFailed(FlowError)
        case reviewTapped
        case shareFinished(Bool)
        case shareTapped
        case spendableUpdated(String?)
        case storedCardsUpdated(hasCards: Bool, isCurrentHandable: Bool)

        enum Delegate: Equatable {
            case exitFlow
            case openSavedCards
        }
    }

    private enum CancelId {
        case observeCards
        case reconcile
        case confirmWatch
    }

    @Dependency(\.localAuthentication) var localAuthentication
    @Dependency(\.giftCardStorage) var giftCardStorage
    @Dependency(\.mainQueue) var mainQueue
    @Dependency(\.sdkSynchronizer) var sdkSynchronizer

    var body: some Reducer<State, Action> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .onAppear:
                let currentCardId = state.quote?.card.id
                return .merge(
                    .run { _ in
                        // Picks up any card whose funding mined while nothing was watching,
                        // because a previous run was killed between broadcast and the next block.
                        await ConfirmGiftCardFunding().reconcileAndObserve()
                    }
                    .cancellable(id: CancelId.reconcile, cancelInFlight: true),
                    .run { send in
                        for await cards in giftCardStorage.observe() {
                            let visible = cards.contains { $0.hasFundingHistory }
                            let handable = currentCardId
                                .flatMap { id in cards.first { $0.id == id } }?
                                .canBeHandedOff ?? true
                            await send(.storedCardsUpdated(hasCards: visible, isCurrentHandable: handable))
                        }
                    }
                    .cancellable(id: CancelId.observeCards, cancelInFlight: true),
                    .run { send in
                        @Shared(.inMemory(.selectedWalletAccount)) var selectedWalletAccount: WalletAccount?
                        guard
                            let account = selectedWalletAccount,
                            let balances = try? await sdkSynchronizer.getAccountsBalances(),
                            let spendable = balances[account.id]?.shieldedSpendableValue
                        else {
                            await send(.spendableUpdated(nil))
                            return
                        }
                        await send(.spendableUpdated(giftAmountText(spendable)))
                    }
                )

            case .spendableUpdated(let text):
                state.spendableBalanceText = text
                return .none

            case let .storedCardsUpdated(hasCards, isCurrentHandable):
                state.hasStoredCards = hasCards
                if state.quote != nil {
                    state.isReadyCardHandable = isCurrentHandable
                }
                return .none

            case .binding(\.amountInput):
                state.amountInput = DecimalAmountInput.sanitized(state.amountInput, fractionDigits: 8)
                state.error = nil
                return .none

            case .binding(\.message):
                state.error = nil
                return .none

            case .binding:
                return .none

            case .expiryChanged(let expiry):
                state.expiry = expiry
                state.error = nil
                return .none

            case .reviewTapped:
                guard state.stage == .details else { return .none }
                guard let amount = state.typedAmount else {
                    state.error = .amountInvalid
                    return .none
                }
                let trimmed = state.message.trimmingCharacters(in: .whitespacesAndNewlines)
                let inputs = PreparedInputs(
                    amountZatoshi: amount.amount,
                    message: trimmed.isEmpty ? nil : trimmed,
                    expiry: state.expiry
                )
                // Reuse the draft only when nothing it was minted for has changed: the amount,
                // the message and the expiry are all baked into the record and the link.
                let reusable = state.preparedFor == inputs ? state.quote?.card : nil
                state.stage = .preparing
                state.error = nil
                return .run { send in
                    do {
                        let quote = try await FundGiftCard().prepare(
                            amount: amount,
                            message: inputs.message,
                            expiresAt: inputs.expiry.expiresAt,
                            existing: reusable
                        )
                        await send(.prepared(quote, inputs))
                    } catch {
                        await send(.prepareFailed(FlowError(preparing: error)))
                    }
                }

            case let .prepared(quote, inputs):
                state.stage = .review
                state.quote = quote
                state.link = quote.link
                state.preparedFor = inputs
                state.isReadyCardHandable = true
                state.error = nil
                return .none

            case .prepareFailed(let error):
                state.stage = .details
                state.error = error
                return .none

            case .fundTapped:
                guard state.stage == .review, state.canConfirm, state.quote != nil else { return .none }
                state.isAuthenticating = true
                state.error = nil
                return .run { send in
                    await send(.authenticationFinished(await localAuthentication.authenticate()))
                }

            case .authenticationFinished(let authenticated):
                state.isAuthenticating = false
                guard authenticated else {
                    state.error = .authenticationFailed
                    return .none
                }
                guard let quote = state.quote else { return .none }
                state.stage = .funding
                return .run { send in
                    do {
                        let txid = try await FundGiftCard().submit(quote)
                        await send(.funded(txid))
                    } catch {
                        await send(.fundingFailed((error as? GiftFundingError).map(FlowError.init) ?? .submitUncertain))
                    }
                }

            case .funded(let txid):
                state.stage = .ready
                state.error = nil
                guard let cardId = state.quote?.card.id else { return .none }
                // Detached from the button: the card is already shareable, and this only advances
                // the record from submitted to funded once a block lands behind the transaction.
                return .run { _ in
                    await ConfirmGiftCardFunding()(cardId: cardId, fundingTxid: txid)
                }
                .cancellable(id: CancelId.confirmWatch, cancelInFlight: true)

            case .fundingFailed(let error):
                state.stage = .review
                state.error = error
                guard error == .submitUncertain else { return .none }
                return .run { _ in
                    await ConfirmGiftCardFunding().reconcileAndObserve()
                }
                .cancellable(id: CancelId.reconcile, cancelInFlight: true)

            case .shareTapped:
                guard state.visibleStage == .ready, let cardId = state.quote?.card.id else { return .none }
                state.error = nil
                return .run { send in
                    // Re-read the custody record immediately before its bearer link can leave the
                    // device; the stored record rebuilds the link.
                    if let handOff = await ShareGiftLink().currentHandOff(cardId: cardId) {
                        await send(.binding(.set(\.shareLink, handOff.link)))
                    } else {
                        await send(.handOffRefused)
                    }
                }

            case .handOffRefused:
                state.isReadyCardHandable = false
                return .none

            case .shareFinished(let completed):
                state.shareLink = nil
                guard completed, let cardId = state.quote?.card.id else { return .none }
                return .run { _ in
                    // Best-effort: the link is already out, so failing to record must not read as
                    // a failed share.
                    await ShareGiftLink().markHandedOut(cardId: cardId)
                }

            case .backTapped:
                switch state.visibleStage {
                case .details, .ready, .unavailable:
                    return .send(.delegate(.exitFlow))
                case .review:
                    guard !state.isAuthenticating else { return .none }
                    state.stage = .details
                    state.error = nil
                    return .none
                case .preparing, .funding:
                    return .none
                }

            case .openSavedCardsTapped:
                guard state.canOpenSavedCards else { return .none }
                return .send(.delegate(.openSavedCards))

            case .delegate:
                return .none
            }
        }
    }
}

extension GiftCard.Expiry {
    var expiresAt: Date? {
        guard self != .never else { return nil }
        return Date.now.addingTimeInterval(TimeInterval(rawValue) * 24 * 60 * 60)
    }
}

private extension GiftCard.FlowError {
    init(_ error: GiftFundingError) {
        switch error {
        case .insufficientFunds: self = .insufficientFunds
        case .proposalFailed: self = .proposalFailed
        case .submitUncertain: self = .submitUncertain
        }
    }

    /// Includes a `GiftLinkError` out of the encode; anything unrecognised is a mint failure.
    init(preparing error: Error) {
        if let funding = error as? GiftFundingError {
            self.init(funding)
            return
        }
        if let creation = error as? GiftCardCreationError {
            switch creation {
            case .invalidAmount: self = .amountInvalid
            case .messageTooLong: self = .messageTooLong
            case .keystoneUnsupported: self = .keystoneUnsupported
            case .unsupportedNetwork: self = .unsupportedNetwork
            case .chainTipUnavailable: self = .chainTipUnavailable
            case .persistFailed: self = .persistFailed
            }
            return
        }
        self = .mintFailed
    }
}

// The link is the money, and the quote holds the ephemeral mnemonic. Debug dumps of the state
// must never carry either.
extension GiftCard.State: CustomDumpStringConvertible {
    var customDumpDescription: String {
        "GiftCard.State(stage: \(stage), error: \(String(describing: error)), redacted)"
    }
}
