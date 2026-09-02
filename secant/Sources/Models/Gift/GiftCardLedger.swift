// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

/// A mutation that would have lost track of a card's funds, refused.
struct GiftCardTransitionError: Error, Equatable {
    let message: String
}

/// The transition rules over the stored card list, kept pure so every one of them is directly
/// testable and so the storage client is nothing but an actor and a write.
///
/// The status is a *delivery* ordinal, not a description of the money: funding submitted but not
/// yet mined is `draft` carrying a `fundingTxid`. That is what lets a sender share in the ~75
/// seconds before the funding mines without the record claiming it has.
enum GiftCardLedger {
    /// Callers must complete this *before* submitting funding: a crash in between otherwise loses
    /// the ephemeral seed, and with it the money, permanently.
    ///
    /// Minting supersedes any `isAbandonedDraft` already on file, which is the only discard in
    /// this ledger and the only one that can be. Without it every edited amount leaves one behind
    /// for good, in the single blob each mutation reads and rewrites. Tied to minting rather than
    /// run on a timer because a sweep would have to decide when a draft is old enough to be dead,
    /// and getting that wrong is unrecoverable.
    static func add(_ cards: [StoredGiftCard], card: StoredGiftCard) throws -> [StoredGiftCard] {
        try ensure(!cards.contains { $0.id == card.id }, "Gift card \(card.id) already exists")
        try ensure(card.status == .draft, "A new gift card starts as draft")
        try ensure(card.fundingTxid == nil, "A new gift card has not been funded yet")
        try ensure(!card.hasFundingHistory, "A new gift card has no funding history")
        return cards.filter { !$0.isAbandonedDraft } + [card]
    }

    /// Written before local creation because the SDK's background resubmitter may automatically
    /// submit any outgoing transaction stored in its database, even when the app has not called
    /// submit yet. This is what makes the SDK boundary crash-safe.
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

    /// Leaves the card `draft` until it mines. Idempotent for the same txid.
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

    /// Only legitimate after a fully-synced wallet read. The history record keeps a shared card
    /// visible while clearing the double-funding gate.
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

    /// Keeps every expired id, not just the newest: after repeated recovery an old expired row
    /// must never be selected as the active transaction of a later attempt merely because it still
    /// targets the same address.
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

    /// Recovery for a process death between SDK creation and recording the new txid. Archiving and
    /// attaching must land in one write.
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

    /// The weakest of the three guards, deliberately: a broadcast merely *started* is enough. A
    /// card whose outcome was never seen has to be shareable too, because its money may already
    /// have gone and then the link is the only route to it. Refusing that would leave a card the
    /// UI offers to hand out and the ledger will not record — permanently unshareable, permanently
    /// blocking the reset guard.
    static func markShared(_ cards: [StoredGiftCard], id: String, at: String) throws -> [StoredGiftCard] {
        try cards.replacing(id) { card in
            try ensure(card.hasFundingAttempt, "Gift card \(id) has not been funded yet")
            return card.advancedTo(.shared, at: at)
        }
    }

    static func recordChecked(_ cards: [StoredGiftCard], id: String, at: String) throws -> [StoredGiftCard] {
        try cards.replacing(id) { card in
            var next = card
            next.lastCheckedAt = at
            next.updatedAt = at
            return next
        }
    }

    /// Backfills `fundingMinedAt`: a finalized claim spend is itself proof the funding mined.
    static func markClaimed(_ cards: [StoredGiftCard], id: String, at: String) throws -> [StoredGiftCard] {
        try cards.replacing(id) { card in
            try ensure(card.fundingTxid != nil, "Gift card \(id) has not been funded yet")
            var next = card.advancedTo(.claimed, at: at)
            next.fundingMinedAt = card.fundingMinedAt ?? at
            return next
        }
    }

    /// Whether `accountUuid` — or any account, when it is nil — still owns funds that only this
    /// device knows how to reach. Production only ever asks the nil question, to guard the paths
    /// that destroy the gift keychain records; the per-account filter is exercised by tests.
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
