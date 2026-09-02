// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

/// A mutation that would have lost track of a card's funds, refused.
struct GiftCardTransitionError: Error, Equatable {
    let message: String
}

/// The transition rules over the stored card list, kept pure so every one of them is directly
/// testable and so the storage client is nothing but an actor and a write.
///
/// The invariants, each of which is money:
///
///  - Status only ever advances. A card that regresses is a card the UI stops accounting for.
///  - A card is never recorded `funded` without a funding txid.
///  - A card is never recorded settled without evidence its funding reached the card.
///  - A mutation never drops a record or rewrites its key material.
///
/// The status is a *delivery* ordinal, not a description of the money: funding submitted but not
/// yet mined is `draft` carrying a `fundingTxid`. That is what lets a sender share in the ~75
/// seconds before the funding mines without the record claiming it has. The confirmation itself
/// lives off the enum, in `fundingMinedAt`, and every caller that needs to know whether the money
/// is really on the card asks `isFundingMined`.
enum GiftCardLedger {
    /// Persists a freshly minted card. Callers must complete this *before* submitting funding: a
    /// crash in between otherwise loses the ephemeral seed, and with it the money, permanently.
    ///
    /// Minting supersedes any `isAbandonedDraft` already on file, which is the only discard in
    /// this ledger and the only one that can be: a draft with no funding attempt is a record of an
    /// address no transaction was ever sent to. Without it every edited amount leaves one behind
    /// for good — a store that only grows, holding key material that unlocks nothing, in the
    /// single blob each mutation reads and rewrites.
    ///
    /// Tied to minting rather than run on a timer on purpose. A sweep would have to decide when a
    /// draft is old enough to be dead, and getting that wrong is unrecoverable; here the answer is
    /// structural, and the store's actor makes the read-and-replace atomic.
    static func add(_ cards: [StoredGiftCard], card: StoredGiftCard) throws -> [StoredGiftCard] {
        try ensure(!cards.contains { $0.id == card.id }, "Gift card \(card.id) already exists")
        try ensure(card.status == .draft, "A new gift card starts as draft")
        try ensure(card.fundingTxid == nil, "A new gift card has not been funded yet")
        try ensure(!card.hasFundingHistory, "A new gift card has no funding history")
        return cards.filter { !$0.isAbandonedDraft } + [card]
    }

    /// Marks that the SDK funding pipeline is about to be started.
    ///
    /// This is what makes the SDK boundary crash-safe. It is written before local creation because
    /// the SDK's background resubmitter may automatically submit any outgoing transaction stored
    /// in its database, even when the app has not called submit yet.
    static func setFundingAttemptedAt(_ cards: [StoredGiftCard], id: String, at: String) throws -> [StoredGiftCard] {
        try cards.replacing(id) { card in
            try ensure(!card.hasFundingAttempt, "Gift card \(id) funding was already started")
            try ensure(!card.isFundingMined, "Gift card \(id) is already funded")
            try ensure(card.status != .claimed, "Gift card \(id) is already collected")
            var next = card
            next.fundingTxid = nil
            next.fundingCreatedAt = nil
            next.fundingAttemptedAt = at
            next.fundingSubmittedAt = nil
            next.updatedAt = at
            return next
        }
    }

    /// Attaches the txid created after `setFundingAttemptedAt` established the durable gate.
    static func recordFundingCreated(
        _ cards: [StoredGiftCard],
        id: String,
        fundingTxid: String,
        at: String
    ) throws -> [StoredGiftCard] {
        try cards.replacing(id) { card in
            try ensure(card.fundingAttemptedAt != nil, "Gift card \(id) funding was not started durably")
            try ensure(card.fundingTxid == nil, "Gift card \(id) already has a funding transaction")
            try ensure(!fundingTxid.isBlank, "Gift card \(id) needs a funding txid")
            try ensure(
                !card.fundingFailures.contains { $0.transactionId == fundingTxid },
                "Gift card \(id) cannot reactivate an expired funding transaction"
            )
            var next = card
            next.fundingTxid = fundingTxid
            next.fundingCreatedAt = at
            next.fundingSubmittedAt = nil
            next.updatedAt = at
            return next
        }
    }

    /// Records the txid of a submitted funding transaction, leaving the card `draft` until it
    /// mines. Idempotent for the same txid, so a retried submit is not an error.
    static func recordFundingSubmitted(
        _ cards: [StoredGiftCard],
        id: String,
        fundingTxid: String,
        at: String
    ) throws -> [StoredGiftCard] {
        try cards.replacing(id) { card in
            try ensure(!fundingTxid.isBlank, "Gift card \(id) needs a funding txid")
            try ensure(
                card.fundingTxid == nil || card.fundingTxid == fundingTxid,
                "Gift card \(id) is already funded by a different transaction"
            )
            try ensure(
                !card.fundingFailures.contains { $0.transactionId == fundingTxid },
                "Gift card \(id) cannot resubmit an expired funding transaction"
            )
            var next = card
            next.fundingTxid = fundingTxid
            next.fundingAttemptedAt = nil
            next.fundingSubmittedAt = at
            next.updatedAt = at
            return next
        }
    }

    /// Resolves an attempt whose transaction was never created, after a fully-synced wallet read.
    /// The history record keeps a shared card visible while clearing the double-funding gate.
    static func markFundingNotCreated(_ cards: [StoredGiftCard], id: String, at: String) throws -> [StoredGiftCard] {
        try cards.replacing(id) { card in
            if case .retryable(let lastFailure) = card.fundingLifecycle, lastFailure.reason == .noTransaction {
                return card
            }
            guard case .attempting(let attemptedAt) = card.fundingLifecycle else {
                throw GiftCardTransitionError(message: "Gift card \(id) is not awaiting transaction creation")
            }
            return card.withFailedFunding(
                [try GiftFundingFailure(reason: .noTransaction, attemptedAt: attemptedAt, detectedAt: at)],
                at: at
            )
        }
    }

    /// Resolves every expired transaction belonging to the current attempt.
    ///
    /// Keeping all ids matters after repeated recovery: an old expired row must never be selected
    /// as the active transaction of a later attempt merely because it still targets the same
    /// address.
    static func markFundingExpired(
        _ cards: [StoredGiftCard],
        id: String,
        fundingTxids: Set<String>,
        at: String
    ) throws -> [StoredGiftCard] {
        try cards.replacing(id) { card in
            try ensure(!fundingTxids.isEmpty, "Gift card \(id) needs an expired funding txid")
            try ensure(!card.isFundingMined, "Gift card \(id) funding already mined")
            try ensure(card.status != .claimed, "Gift card \(id) is already collected")
            if let active = card.fundingTxid {
                try ensure(fundingTxids.contains(active), "Gift card \(id) active funding transaction has not expired")
            }
            let attemptedAt = card.currentFundingAttemptedAt
            let failures = try fundingTxids
                .filter { txid in !card.fundingFailures.contains { $0.transactionId == txid } }
                .sorted()
                .map { txid in
                    try GiftFundingFailure(reason: .expired, attemptedAt: attemptedAt, transactionId: txid, detectedAt: at)
                }
            if failures.isEmpty && card.isFundingRetryable { return card }
            try ensure(!failures.isEmpty, "Gift card \(id) has no new expired funding transaction")
            return card.withFailedFunding(failures, at: at)
        }
    }

    /// Archives expired candidates and attaches the single still-live transaction atomically.
    /// This is recovery for a process death between SDK creation and recording the new txid.
    static func replaceExpiredFunding(
        _ cards: [StoredGiftCard],
        id: String,
        expiredFundingTxids: Set<String>,
        activeFundingTxid: String,
        at: String
    ) throws -> [StoredGiftCard] {
        try cards.replacing(id) { card in
            try ensure(!activeFundingTxid.isBlank, "Gift card \(id) needs an active funding txid")
            try ensure(!expiredFundingTxids.contains(activeFundingTxid), "Gift card \(id) active transaction cannot be expired")
            try ensure(
                !card.fundingFailures.contains { $0.transactionId == activeFundingTxid },
                "Gift card \(id) cannot reactivate an expired funding transaction"
            )
            try ensure(!card.isFundingMined, "Gift card \(id) funding already mined")
            if let active = card.fundingTxid {
                try ensure(expiredFundingTxids.contains(active), "Gift card \(id) cannot replace a live funding transaction")
            }
            let attemptedAt = card.currentFundingAttemptedAt
            let failures = try expiredFundingTxids
                .filter { txid in !card.fundingFailures.contains { $0.transactionId == txid } }
                .sorted()
                .map { txid in
                    try GiftFundingFailure(reason: .expired, attemptedAt: attemptedAt, transactionId: txid, detectedAt: at)
                }
            var next = card
            next.fundingTxid = activeFundingTxid
            next.fundingCreatedAt = at
            next.fundingAttemptedAt = attemptedAt ?? at
            next.fundingSubmittedAt = nil
            next.fundingFailures = card.fundingFailures + failures
            next.updatedAt = at
            return next
        }
    }

    /// Marks a card funded once its transaction has mined. The txid guard is the point: a card
    /// recorded as funded with no transaction behind it is one the sender believes exists and the
    /// recipient cannot claim.
    ///
    /// Also records `fundingMinedAt`, which is the half that survives a card already past
    /// `funded`. First observation wins — the field is when the funding was *seen* to have mined,
    /// and a second sweep over the same transaction is not a new event.
    static func markFunded(
        _ cards: [StoredGiftCard],
        id: String,
        fundingTxid: String,
        at: String
    ) throws -> [StoredGiftCard] {
        try cards.replacing(id) { card in
            try ensure(!fundingTxid.isBlank, "Gift card \(id) needs a funding txid")
            try ensure(
                card.fundingTxid == nil || card.fundingTxid == fundingTxid,
                "Gift card \(id) is already funded by a different transaction"
            )
            try ensure(
                !card.fundingFailures.contains { $0.transactionId == fundingTxid },
                "Gift card \(id) cannot mine an expired funding transaction"
            )
            // The transaction is attached before the status advances, so the record's invariants
            // never see a funded card with no txid behind it.
            var next = card
            next.fundingTxid = fundingTxid
            next.fundingAttemptedAt = nil
            next.fundingSubmittedAt = card.fundingSubmittedAt ?? at
            next.fundingMinedAt = card.fundingMinedAt ?? at
            return next.advancedTo(.funded, at: at)
        }
    }

    /// Marks the link as handed out. Requires only that a broadcast was *started*, not that
    /// funding has mined or that the submission outcome was observed.
    ///
    /// The weakest of the three guards, deliberately. A card whose broadcast outcome was never
    /// seen has to be shareable too: its money may already have gone, and then the link is the
    /// only route to it. Refusing that would leave a card the UI offers to hand out and the ledger
    /// will not record — permanently unshareable, permanently blocking the reset guard. What stays
    /// forbidden is the one case that hands out a link to an address nothing was ever sent to.
    static func markShared(_ cards: [StoredGiftCard], id: String, at: String) throws -> [StoredGiftCard] {
        try cards.replacing(id) { card in
            try ensure(card.hasFundingAttempt, "Gift card \(id) has not been funded yet")
            return card.advancedTo(.shared, at: at)
        }
    }

    /// Records that the card was scanned and still held its funds. No status change: nothing moved.
    static func recordChecked(_ cards: [StoredGiftCard], id: String, at: String) throws -> [StoredGiftCard] {
        try cards.replacing(id) { card in
            var next = card
            next.lastCheckedAt = at
            next.updatedAt = at
            return next
        }
    }

    /// Marks a card collected after its funding and finalized claim spend are observed. The
    /// observation also backfills `fundingMinedAt`.
    static func markClaimed(_ cards: [StoredGiftCard], id: String, at: String) throws -> [StoredGiftCard] {
        try cards.replacing(id) { card in
            try ensure(card.fundingTxid != nil, "Gift card \(id) has not been funded yet")
            var next = card.advancedTo(.claimed, at: at)
            next.fundingMinedAt = card.fundingMinedAt ?? at
            return next
        }
    }

    /// Whether `accountUuid` — or any account, when it is nil — still owns funds that only this
    /// device knows how to reach. Blocks deleting the account, and with a nil `accountUuid` blocks
    /// the wallet wipe, which clears them all.
    static func hasUnsharedFunds(_ cards: [StoredGiftCard], accountUuid: String? = nil) -> Bool {
        cards.contains { $0.isUnsharedFunds && (accountUuid == nil || $0.sourceAccountUuid == accountUuid) }
    }

    private static func ensure(_ condition: Bool, _ message: String) throws {
        if !condition { throw GiftCardTransitionError(message: message) }
    }
}

private extension Array where Element == StoredGiftCard {
    func replacing(_ id: String, _ transform: (StoredGiftCard) throws -> StoredGiftCard) throws -> [StoredGiftCard] {
        guard contains(where: { $0.id == id }) else { throw GiftCardTransitionError(message: "No gift card \(id)") }
        return try map { card in
            guard card.id == id else { return card }
            let next = try transform(card)
            try next.validate()
            return next
        }
    }
}

private extension StoredGiftCard {
    // Taking the maximum rather than assigning is what makes the status monotonic by
    // construction: a card whose funding mines after its link was shared gets the confirmation
    // recorded without being walked back out of shared, and no ordering of callbacks can produce
    // a regression.
    func advancedTo(_ next: GiftCardStatus, at: String) -> StoredGiftCard {
        var card = self
        card.status = max(card.status, next)
        card.updatedAt = at
        return card
    }

    var currentFundingAttemptedAt: String? {
        fundingAttemptedAt ?? fundingCreatedAt ?? fundingSubmittedAt
    }

    func withFailedFunding(_ failures: [GiftFundingFailure], at: String) -> StoredGiftCard {
        var card = self
        card.fundingTxid = nil
        card.fundingCreatedAt = nil
        card.fundingAttemptedAt = nil
        card.fundingSubmittedAt = nil
        card.fundingFailures = fundingFailures + failures
        card.updatedAt = at
        return card
    }
}
