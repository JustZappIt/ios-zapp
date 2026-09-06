// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
@preconcurrency import ZcashLightClientKit

/// The recovery path for cards the sender never finished handing out.
///
/// A card's ephemeral seed is random rather than derived from the wallet seed and there is no
/// reclaim, so leaving the create flow must not be the end of the story. Every stored card is
/// re-shareable from here, because the record keeps everything the link needs.
@Reducer
struct GiftCardList {
    /// How far a stored card got, flattened for display. `submitted` and `unresolved` are the
    /// states the enum on disk cannot express — a draft carrying a funding txid, and one carrying
    /// only an unresolved broadcast attempt. Both may already hold real money.
    enum ListStatus: Equatable {
        case unfunded
        /// Every previous attempt is terminal. The same card can be deliberately funded again.
        case retryable
        /// Broadcast started and its outcome was never seen. Money gone until proven otherwise.
        case unresolved
        case submitted
        case funded
        case shared
        /// Collected by whoever held the link. Terminal: nothing left to hand out or to lose.
        case claimed
    }

    /// Why the check control is inert. A dead control with no reason beside it reads as broken.
    enum CheckBlocked: Equatable {
        case noTransaction
        case anotherRunning
    }

    enum CheckControl: Equatable {
        case hidden
        case blocked(CheckBlocked)
        case ready
        /// Fraction stays nil until the SDK measures something, which is a while into a scan.
        case running(fraction: Float?)
    }

    enum FundingControl: Equatable {
        case hidden
        case ready
        case running
    }

    enum ListError: Equatable {
        case linkFailed
        case shareFailed
        case checkUnreachable
        case checkFailed
        case retryAuthenticationFailed
        case retryInsufficientFunds
        case retryFailed
        case retryUncertain
    }

    /// A finding rather than a failure — rendered muted, not in the danger colour.
    enum ListNotice: Equatable {
        case checkFundingPending
        case retrySubmitted
    }

    /// One card. Deliberately carries no mnemonic and no link: the link is rebuilt from storage
    /// only when the sender asks for it, so a state dump of this list is not a bearer secret.
    struct Item: Equatable, Identifiable {
        let id: String
        let amountText: String
        let fiatText: String?
        let tier: GiftCardTier
        let createdAtText: String?
        let message: String?
        let status: ListStatus
        let expiryText: String?
        let isExpired: Bool
        let lastCheckedAtText: String?
        let isLastCheckRecent: Bool
        var check: CheckControl
        var funding: FundingControl
        let canHandOff: Bool
    }

    /// Freshly-priced spend shown before authentication and transaction creation.
    struct RetryReview: Equatable {
        let cardId: String
        let amountText: String
        let claimFeeReserveText: String
        let networkFeeText: String
        let totalText: String
        let message: String?
    }

    @ObservableState
    struct State: Equatable {
        var items: [Item] = []
        var isCorrupted = false
        var error: ListError?
        var notice: ListNotice?
        var checkingId: String?
        var checkFraction: Float?
        var retryingId: String?
        var retryReview: RetryReview?
        var shareLink: String?
        var shareCardId: String?
        var isForeground = true
        @Shared(.inMemory(.exchangeRate)) var currencyConversion: CurrencyConversion? = nil
    }

    enum Action {
        case backTapped
        case cardsUpdated([Item], isCorrupted: Bool)
        case checkFinished(GiftCardCheckResult)
        case checkProgressed(Float?)
        case checkTapped(String)
        case copyTapped(String)
        case delegate(Delegate)
        case foregroundChanged(Bool)
        case linkRebuilt(cardId: String, link: String)
        case linkFailed
        case onAppear
        case retryConfirmTapped
        case retryDismissTapped
        case retryFinished
        case retryFailed(ListError)
        case retryPriced(RetryReview, GiftFundingQuote)
        case retryTapped(String)
        case shareFailed
        case shareFinished(Bool)
        case shareTapped(String)

        enum Delegate: Equatable {
            case exitFlow
        }
    }

    private enum CancelId {
        case observe
        case reconcile
        case check
        case retry
        case confirmWatch
    }

    @Dependency(\.date) var date
    @Dependency(\.giftCardStorage) var giftCardStorage
    /// A dependency rather than a stored property; see `GiftRetryQuoteStore`.
    @Dependency(\.giftRetryQuote) var retryBox
    @Dependency(\.localAuthentication) var localAuthentication
    @Dependency(\.pasteboard) var pasteboard

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                let conversion = state.currencyConversion
                return .merge(
                    .run { _ in
                        // Anything whose funding mined while nothing was watching still reads as
                        // a draft on disk.
                        await ConfirmGiftCardFunding().reconcileAndObserve()
                    }
                    .cancellable(id: CancelId.reconcile, cancelInFlight: true),
                    .run { _ in
                        await ConfirmGiftClaim().reconcile()
                    },
                    .run { send in
                        do {
                            for await cards in giftCardStorage.observe() {
                                await send(.cardsUpdated(Self.items(from: cards, conversion: conversion), isCorrupted: false))
                            }
                        }
                    }
                    .cancellable(id: CancelId.observe, cancelInFlight: true),
                    .run { send in
                        // The observe stream seeds nothing from a corrupt store; a direct read is
                        // what can tell the sender something is wrong with it.
                        if (try? await giftCardStorage.getAll()) == nil {
                            await send(.cardsUpdated([], isCorrupted: true))
                        }
                    }
                )

            case let .cardsUpdated(items, isCorrupted):
                state.isCorrupted = isCorrupted
                state.items = Self.decorated(items, state: state)
                return .none

            case .foregroundChanged(let foreground):
                state.isForeground = foreground
                guard !foreground, state.checkingId != nil else { return .none }
                state.checkingId = nil
                state.checkFraction = nil
                state.items = Self.decorated(state.items, state: state)
                return .cancel(id: CancelId.check)

            case .checkTapped(let cardId):
                guard state.isForeground else { return .none }
                if state.checkingId != nil {
                    // The scan can legitimately run for minutes, so a stop is the only honest
                    // control: there is no duration at which giving up is automatically right.
                    state.checkingId = nil
                    state.checkFraction = nil
                    state.items = Self.decorated(state.items, state: state)
                    return .cancel(id: CancelId.check)
                }
                state.checkingId = cardId
                state.checkFraction = nil
                state.error = nil
                state.notice = nil
                state.items = Self.decorated(state.items, state: state)
                return .run { send in
                    let result = await CheckGiftCardClaimed()(
                        cardId: cardId,
                        onProgress: { progress in
                            // Below one percent the figure rounds to "0%", which reads as stalled
                            // rather than starting.
                            let fraction = progress.fraction >= 0.01 ? progress.fraction : nil
                            Task { await send(.checkProgressed(fraction)) }
                        }
                    )
                    await send(.checkFinished(result))
                }
                .cancellable(id: CancelId.check, cancelInFlight: true)

            case .checkProgressed(let fraction):
                state.checkFraction = fraction
                state.items = Self.decorated(state.items, state: state)
                return .none

            case .checkFinished(let result):
                state.checkingId = nil
                state.checkFraction = nil
                switch result {
                case .unreachable:
                    state.error = .checkUnreachable
                case .unknown:
                    state.error = .checkFailed
                case .fundingPending:
                    // Not an error: the scan worked and the answer is "not there yet".
                    state.notice = .checkFundingPending
                case .collected, .waiting, .notFunded:
                    break
                }
                state.items = Self.decorated(state.items, state: state)
                return .none

            case .shareTapped(let cardId):
                state.error = nil
                state.notice = nil
                return rebuildLink(cardId: cardId)

            case .copyTapped(let cardId):
                state.error = nil
                state.notice = nil
                return .run { send in
                    guard let handOff = await ShareGiftLink().currentHandOff(cardId: cardId) else {
                        await send(.linkFailed)
                        return
                    }
                    pasteboard.setString(RedactableString(handOff.link))
                    // Clipboard is an affirmative act that reports no outcome; treating a copied
                    // link as private would block wallet deletion over a card genuinely given
                    // away.
                    if await !ShareGiftLink().markHandedOut(cardId: cardId) {
                        await send(.shareFailed)
                    }
                }

            case let .linkRebuilt(cardId, link):
                state.shareCardId = cardId
                state.shareLink = link
                return .none

            case .linkFailed:
                state.error = .linkFailed
                return .none

            case .shareFailed:
                // Not the share failing — the record of it, which is what releases the reset guard.
                state.error = .shareFailed
                return .none

            case .shareFinished(let completed):
                let cardId = state.shareCardId
                state.shareLink = nil
                state.shareCardId = nil
                guard completed, let cardId else { return .none }
                return .run { send in
                    if await !ShareGiftLink().markHandedOut(cardId: cardId) {
                        await send(.shareFailed)
                    }
                }

            case .retryTapped(let cardId):
                guard state.retryingId == nil, state.retryReview == nil else { return .none }
                state.retryingId = cardId
                state.error = nil
                state.notice = nil
                state.items = Self.decorated(state.items, state: state)
                return .run { send in
                    do {
                        guard let card = try await giftCardStorage.get(cardId), card.isFundingRetryable else {
                            await send(.retryFailed(.retryFailed))
                            return
                        }
                        // Prices the retry; this step cannot create or submit a transaction.
                        let quote = try await FundGiftCard().prepare(
                            amount: Zatoshi(card.amountZatoshi),
                            message: card.message,
                            existing: card
                        )
                        let review = RetryReview(
                            cardId: cardId,
                            amountText: giftAmountText(quote.cardAmount),
                            claimFeeReserveText: giftAmountText(quote.claimFeeReserve),
                            networkFeeText: giftAmountText(quote.networkFee),
                            totalText: giftAmountText(quote.total),
                            message: quote.card.message
                        )
                        await send(.retryPriced(review, quote))
                    } catch {
                        await send(.retryFailed(Self.retryError(error)))
                    }
                }
                .cancellable(id: CancelId.retry, cancelInFlight: true)

            case let .retryPriced(review, quote):
                retryBox.put(quote)
                state.retryingId = nil
                state.retryReview = review
                state.items = Self.decorated(state.items, state: state)
                return .none

            case .retryConfirmTapped:
                guard let quote = retryBox.take(), let review = state.retryReview else { return .none }
                state.retryReview = nil
                state.retryingId = review.cardId
                state.items = Self.decorated(state.items, state: state)
                return .run { send in
                    guard await localAuthentication.authenticate() else {
                        await send(.retryFailed(.retryAuthenticationFailed))
                        return
                    }
                    do {
                        // The only retry action that may spend.
                        let txid = try await FundGiftCard().submit(quote)
                        await send(.retryFinished)
                        await ConfirmGiftCardFunding()(cardId: quote.card.id, fundingTxid: txid)
                    } catch {
                        await send(.retryFailed(Self.retryError(error)))
                    }
                }
                .cancellable(id: CancelId.retry, cancelInFlight: true)

            case .retryDismissTapped:
                guard state.retryingId == nil else { return .none }
                retryBox.put(nil)
                state.retryReview = nil
                return .none

            case .retryFinished:
                retryBox.put(nil)
                state.retryingId = nil
                state.notice = .retrySubmitted
                state.items = Self.decorated(state.items, state: state)
                return .none

            case .retryFailed(let error):
                retryBox.put(nil)
                state.retryingId = nil
                state.error = error
                state.items = Self.decorated(state.items, state: state)
                guard error == .retryUncertain else { return .none }
                return .run { _ in
                    await ConfirmGiftCardFunding().reconcileAndObserve()
                }
                .cancellable(id: CancelId.reconcile, cancelInFlight: true)

            case .backTapped:
                return .send(.delegate(.exitFlow))

            case .delegate:
                return .none
            }
        }
    }

    private func rebuildLink(cardId: String) -> Effect<Action> {
        .run { send in
            // Reads the card back rather than closing over it, so a hand-off always encodes what
            // is on disk now.
            guard let handOff = await ShareGiftLink().currentHandOff(cardId: cardId) else {
                await send(.linkFailed)
                return
            }
            await send(.linkRebuilt(cardId: cardId, link: handOff.link))
        }
    }

    private static func retryError(_ error: Error) -> ListError {
        switch error as? GiftFundingError {
        case .insufficientFunds: return .retryInsufficientFunds
        case .submitUncertain: return .retryUncertain
        case .proposalFailed, nil: return .retryFailed
        }
    }

}

extension GiftCardList {
    /// Drafts nothing was ever sent to are invisible (mint artefacts); unshared-funds first, then
    /// newest.
    static func items(from cards: [StoredGiftCard], conversion: CurrencyConversion?) -> [Item] {
        cards
            .filter { $0.hasFundingHistory }
            .sorted { lhs, rhs in
                if lhs.isUnsharedFunds != rhs.isUnsharedFunds {
                    return lhs.isUnsharedFunds
                }
                // Compared as instants, not strings: records written before `instantString` carried
                // milliseconds lack the fractional part, and `.` sorts below `Z`.
                let lhsDate = GiftLinkCodec.parseInstant(lhs.createdAt) ?? .distantPast
                let rhsDate = GiftLinkCodec.parseInstant(rhs.createdAt) ?? .distantPast
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                return lhs.id < rhs.id
            }
            .map { card in
                let status = listStatus(of: card)
                let amount = Zatoshi(card.amountZatoshi)
                var fiat: String?
                if let conversion {
                    let text: String = conversion.convert(amount)
                    fiat = text
                }
                let expiryDate = card.expiresAt.flatMap(GiftLinkCodec.parseInstant)
                return Item(
                    id: card.id,
                    amountText: giftAmountText(amount),
                    fiatText: fiat,
                    tier: giftCardTier(amountZatoshi: card.amountZatoshi, isSettled: status == .claimed),
                    createdAtText: GiftLinkCodec.parseInstant(card.createdAt)?
                        .formatted(date: .abbreviated, time: .omitted),
                    message: card.message,
                    status: status,
                    expiryText: expiryDate?.formatted(date: .abbreviated, time: .omitted),
                    isExpired: expiryDate.map { $0 < Date.now } ?? false,
                    lastCheckedAtText: status == .claimed ? nil : card.lastCheckedAt
                        .flatMap(GiftLinkCodec.parseInstant)?
                        .formatted(date: .abbreviated, time: .omitted),
                    isLastCheckRecent: isRecentCheck(card.lastCheckedAt),
                    check: baseCheckControl(card: card, status: status),
                    funding: status == .retryable ? .ready : .hidden,
                    // An unfunded draft encodes into a link that pays nothing, and a collected
                    // card's link is spent. Unresolved counts as handable: the money may already
                    // have gone, and if it has, the link is the only route.
                    canHandOff: status != .unfunded && status != .retryable && status != .claimed
                )
            }
    }

    /// Strips the previous overlay first — every caller but `.cardsUpdated` passes rows this
    /// already decorated, and folding over its own output is how a finished check stays running
    /// forever.
    private static func decorated(_ items: [Item], state: State) -> [Item] {
        items.map { item in
            var next = item
            next.check = baseCheckControl(of: item.check)
            if next.check == .ready, let checkingId = state.checkingId {
                next.check = item.id == checkingId
                    ? .running(fraction: state.checkFraction)
                    : .blocked(.anotherRunning)
            }
            if item.funding != .hidden {
                next.funding = item.id == state.retryingId ? .running : .ready
            }
            return next
        }
    }

    /// The overlay only ever replaces `.ready`, so it peels back off: `.hidden` and
    /// `.blocked(.noTransaction)` are the record's own answer, anything else started as `.ready`.
    private static func baseCheckControl(of check: CheckControl) -> CheckControl {
        switch check {
        case .hidden, .blocked(.noTransaction):
            return check
        case .ready, .running, .blocked(.anotherRunning):
            return .ready
        }
    }

    private static func baseCheckControl(card: StoredGiftCard, status: ListStatus) -> CheckControl {
        switch status {
        case .claimed, .retryable:
            return .hidden
        default:
            return card.fundingTxid == nil ? .blocked(.noTransaction) : .ready
        }
    }

    private static func listStatus(of card: StoredGiftCard) -> ListStatus {
        if card.status == .claimed { return .claimed }
        if card.isFundingRetryable { return .retryable }
        if !card.isFundingMined && card.fundingAttemptedAt != nil { return .unresolved }
        if !card.isFundingMined && card.isFundingSubmitted { return .submitted }
        if card.status == .shared { return .shared }
        if card.status == .funded { return .funded }
        return .unfunded
    }

    private static func isRecentCheck(_ checkedAt: String?, now: Date = .now) -> Bool {
        guard let checkedAt, let date = GiftLinkCodec.parseInstant(checkedAt) else { return false }
        let age = now.timeIntervalSince(date)
        return age >= 0 && age <= 24 * 60 * 60
    }
}
