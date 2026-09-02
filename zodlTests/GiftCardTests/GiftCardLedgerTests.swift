// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
@testable import zodl_internal

@Suite struct GiftCardLedgerTests {
    private static let id = "card-1"
    private static let otherId = "card-2"
    private static let account = "account-1"
    private static let txid = "f00d"
    private static let otherTxid = "beef"
    private static let created = "2026-08-20T12:00:00Z"
    private static let later = "2026-08-20T12:05:00Z"
    private static let latest = "2026-08-20T12:09:00Z"

    /// BIP-39 test vector for all-zero entropy. Never a real wallet.
    private static let mnemonic =
        "\(String(repeating: "abandon ", count: 23))art"

    @Test func addsADraftCard() throws {
        let cards = try GiftCardLedger.add([], card: card())

        #expect(cards == [try card()])
    }

    @Test func refusesToAddACardWhoseIdIsAlreadyTaken() throws {
        let cards = try GiftCardLedger.add([], card: card())

        // Silently replacing would drop the earlier card's mnemonic, and with it its funds.
        #expect(throws: GiftCardTransitionError.self) {
            try GiftCardLedger.add(cards, card: self.card(amount: 999))
        }
    }

    @Test func refusesToAddACardThatClaimsToBePastDraft() throws {
        #expect(throws: GiftCardTransitionError.self) {
            try GiftCardLedger.add([], card: self.card(status: .funded, txid: Self.txid))
        }
        #expect(throws: GiftCardTransitionError.self) {
            try GiftCardLedger.add([], card: self.card(txid: Self.txid))
        }
    }

    @Test func recordsASubmittedFundingTxidWithoutClaimingTheCardHasMined() throws {
        let cards = try GiftCardLedger.recordFundingSubmitted([card()], id: Self.id, fundingTxid: Self.txid, at: Self.later)

        let single = try #require(cards.first)
        #expect(single.fundingTxid == Self.txid)
        #expect(single.status == .draft)
        #expect(single.updatedAt == Self.later)
    }

    @Test func reRecordingTheSameFundingTxidIsNotAnError() throws {
        let once = try GiftCardLedger.recordFundingSubmitted([card()], id: Self.id, fundingTxid: Self.txid, at: Self.later)

        let twice = try GiftCardLedger.recordFundingSubmitted(once, id: Self.id, fundingTxid: Self.txid, at: Self.later)

        #expect(twice.first?.fundingTxid == Self.txid)
    }

    @Test func refusesASecondFundingTransactionForOneCard() throws {
        let cards = try GiftCardLedger.recordFundingSubmitted([card()], id: Self.id, fundingTxid: Self.txid, at: Self.later)

        #expect(throws: GiftCardTransitionError.self) {
            try GiftCardLedger.recordFundingSubmitted(cards, id: Self.id, fundingTxid: Self.otherTxid, at: Self.later)
        }
    }

    @Test func refusesToAttachALocallyCreatedTransactionBeforeTheDurableStartMarker() throws {
        #expect(throws: GiftCardTransitionError.self) {
            try GiftCardLedger.recordFundingCreated([self.card()], id: Self.id, fundingTxid: Self.txid, at: Self.later)
        }
    }

    @Test func marksACardFunded() throws {
        let cards = try GiftCardLedger.markFunded([card()], id: Self.id, fundingTxid: Self.txid, at: Self.later)

        let single = try #require(cards.first)
        #expect(single.status == .funded)
        #expect(single.fundingTxid == Self.txid)
        #expect(single.updatedAt == Self.later)
    }

    @Test func refusesToMarkACardFundedWithoutATxid() throws {
        // The guard exists so a card can never read as funded with no transaction behind it.
        #expect(throws: GiftCardTransitionError.self) {
            try GiftCardLedger.markFunded([self.card()], id: Self.id, fundingTxid: "", at: Self.later)
        }
        #expect(throws: GiftCardTransitionError.self) {
            try GiftCardLedger.markFunded([self.card()], id: Self.id, fundingTxid: "  ", at: Self.later)
        }
    }

    @Test func neverRegressesACardsStatus() throws {
        let submitted = try GiftCardLedger.recordFundingSubmitted([card()], id: Self.id, fundingTxid: Self.txid, at: Self.later)
        let shared = try GiftCardLedger.markShared(
            try GiftCardLedger.markFunded(submitted, id: Self.id, fundingTxid: Self.txid, at: Self.later),
            id: Self.id,
            at: Self.later
        )

        // Recording the submitted txid must not undo funded, and a mining confirmation that lands
        // after the sender has already shared must not walk the card back out of shared. Both are
        // orderings the real flow produces.
        #expect(try GiftCardLedger.markFunded(submitted, id: Self.id, fundingTxid: Self.txid, at: Self.later).first?.status == .funded)
        #expect(
            try GiftCardLedger.recordFundingSubmitted(
                try GiftCardLedger.markFunded(submitted, id: Self.id, fundingTxid: Self.txid, at: Self.later),
                id: Self.id,
                fundingTxid: Self.txid,
                at: Self.latest
            ).first?.status == .funded
        )
        #expect(try GiftCardLedger.markFunded(shared, id: Self.id, fundingTxid: Self.txid, at: Self.latest).first?.status == .shared)
    }

    @Test func refusesToMarkASharedCardFundedAgainUnderADifferentTransaction() throws {
        let shared = try GiftCardLedger.markShared(
            try GiftCardLedger.markFunded([card()], id: Self.id, fundingTxid: Self.txid, at: Self.later),
            id: Self.id,
            at: Self.later
        )

        #expect(throws: GiftCardTransitionError.self) {
            try GiftCardLedger.markFunded(shared, id: Self.id, fundingTxid: Self.otherTxid, at: Self.later)
        }
    }

    @Test func sharesACardOnceItsFundingHasBeenSubmittedButNotYetMined() throws {
        let submitted = try submitted()

        let shared = try GiftCardLedger.markShared(submitted, id: Self.id, at: Self.later)

        #expect(shared.first?.status == .shared)
    }

    @Test func refusesToShareACardThatWasNeverFunded() throws {
        // Otherwise the sender hands out a link to an address holding nothing.
        #expect(throws: GiftCardTransitionError.self) {
            try GiftCardLedger.markShared([self.card()], id: Self.id, at: Self.later)
        }
    }

    @Test func sharesACardWhoseBroadcastOutcomeWasNeverSeen() throws {
        let unresolved = [try card(attemptedAt: Self.later)]

        // The money may already have left for this card, and then the link is the only route to
        // it. Refusing here left the list offering a hand-off the ledger would not record: shared
        // in the chooser, unshared on disk, and blocking a wallet reset for good.
        #expect(try GiftCardLedger.markShared(unresolved, id: Self.id, at: Self.later).first?.status == .shared)
    }

    @Test func recordsThatFundingMinedOnACardAlreadyShared() throws {
        let shared = try GiftCardLedger.markShared(try submitted(), id: Self.id, at: Self.later)

        let funded = try #require(try GiftCardLedger.markFunded(shared, id: Self.id, fundingTxid: Self.txid, at: Self.latest).first)

        // The status cannot regress out of shared to say this, so the confirmation lives beside
        // it. Without it nothing could ever tell a shared card holding money from one whose
        // funding was still in the mempool — and a collection check turns on exactly that
        // difference.
        #expect(funded.status == .shared)
        #expect(funded.fundingMinedAt == Self.latest)
        #expect(funded.isFundingMined)
    }

    @Test func keepsTheFirstConfirmationWhenFundingIsSweptTwice() throws {
        let funded = try GiftCardLedger.markFunded([card(txid: Self.txid)], id: Self.id, fundingTxid: Self.txid, at: Self.later)

        // When it was seen to have mined, not when something last looked.
        #expect(try GiftCardLedger.markFunded(funded, id: Self.id, fundingTxid: Self.txid, at: Self.latest).first?.fundingMinedAt == Self.later)
    }

    @Test func aSharedCardIsNotEvidenceItsFundingMined() throws {
        let shared = try GiftCardLedger.markShared(try submitted(), id: Self.id, at: Self.later)

        // Sharing is legal in the window between submit and the funding mining, so the rank says
        // only that the link went out.
        #expect(shared.first?.isFundingMined == false)
    }

    @Test func sharingTwiceIsNotAnError() throws {
        let once = try GiftCardLedger.markShared(
            try GiftCardLedger.markFunded([card()], id: Self.id, fundingTxid: Self.txid, at: Self.later),
            id: Self.id,
            at: Self.later
        )

        let twice = try GiftCardLedger.markShared(once, id: Self.id, at: Self.later)

        #expect(twice.first?.status == .shared)
    }

    @Test func rejectsAMutationNamingACardThatIsNotThere() throws {
        #expect(throws: GiftCardTransitionError.self) {
            try GiftCardLedger.markFunded([self.card()], id: "nope", fundingTxid: Self.txid, at: Self.later)
        }
        #expect(throws: GiftCardTransitionError.self) {
            try GiftCardLedger.markShared([self.card()], id: "nope", at: Self.later)
        }
        #expect(throws: GiftCardTransitionError.self) {
            try GiftCardLedger.recordFundingSubmitted([self.card()], id: "nope", fundingTxid: Self.txid, at: Self.later)
        }
    }

    @Test func leavesEveryOtherCardUntouched() throws {
        let others = [try card(id: "a"), try card(id: "b"), try card(id: "c")]

        let mutated = try GiftCardLedger.markFunded(others, id: "b", fundingTxid: Self.txid, at: Self.later)

        #expect(mutated.count == 3)
        #expect(mutated[0] == others[0])
        #expect(mutated[2] == others[2])
        #expect(mutated[0].fundingTxid == nil)
    }

    @Test func reportsFundedCardsWhoseLinksWereNeverShared() throws {
        let draft = try card(id: "draft")
        let submitted = try GiftCardLedger.recordFundingSubmitted([card(id: "submitted")], id: "submitted", fundingTxid: Self.txid, at: Self.later)
        let funded = try GiftCardLedger.markFunded([card(id: "funded")], id: "funded", fundingTxid: Self.txid, at: Self.later)
        let shared = try GiftCardLedger.markShared(funded, id: "funded", at: Self.later)

        #expect(!GiftCardLedger.hasUnsharedFunds([draft], accountUuid: Self.account))
        #expect(GiftCardLedger.hasUnsharedFunds(submitted, accountUuid: Self.account))
        #expect(GiftCardLedger.hasUnsharedFunds(funded, accountUuid: Self.account))
        #expect(!GiftCardLedger.hasUnsharedFunds(shared, accountUuid: Self.account))
    }

    @Test func scopesUnsharedFundsToTheOwningAccount() throws {
        let funded = try GiftCardLedger.markFunded([card()], id: Self.id, fundingTxid: Self.txid, at: Self.later)

        #expect(GiftCardLedger.hasUnsharedFunds(funded, accountUuid: Self.account))
        #expect(!GiftCardLedger.hasUnsharedFunds(funded, accountUuid: "some-other-account"))
    }

    @Test func seesUnsharedFundsInAnyAccountWhenAskedWalletWide() throws {
        let funded = try GiftCardLedger.markFunded([card()], id: Self.id, fundingTxid: Self.txid, at: Self.later)

        // What a wallet wipe has to ask: it clears every account's cards at once.
        #expect(GiftCardLedger.hasUnsharedFunds(funded))
        #expect(!GiftCardLedger.hasUnsharedFunds(try GiftCardLedger.markShared(funded, id: Self.id, at: Self.later)))
        #expect(!GiftCardLedger.hasUnsharedFunds([try card()]))
        #expect(!GiftCardLedger.hasUnsharedFunds([]))
    }

    @Test func countsFundingAsUnresolvedBeforeLocalTransactionCreation() throws {
        let attempted = try GiftCardLedger.setFundingAttemptedAt([card()], id: Self.id, at: Self.later)

        // No txid was written yet, but the SDK's resubmitter may create and submit one after this
        // checkpoint. Guessing "unfunded" here is what would let the wallet be wiped out from
        // under it.
        #expect(attempted.first?.fundingTxid == nil)
        #expect(GiftCardLedger.hasUnsharedFunds(attempted))
        #expect(GiftCardLedger.hasUnsharedFunds(attempted, accountUuid: Self.account))
    }

    @Test func clearsTheAttemptOnceItsOutcomeIsKnown() throws {
        let attempted = try GiftCardLedger.setFundingAttemptedAt([card()], id: Self.id, at: Self.later)
        let created = try GiftCardLedger.recordFundingCreated(attempted, id: Self.id, fundingTxid: Self.txid, at: Self.later)

        // A txid is a stronger record of the same fact, so recording one supersedes the flag.
        #expect(try GiftCardLedger.recordFundingSubmitted(created, id: Self.id, fundingTxid: Self.txid, at: Self.later).first?.fundingAttemptedAt == nil)
        #expect(try GiftCardLedger.markFunded(created, id: Self.id, fundingTxid: Self.txid, at: Self.later).first?.fundingAttemptedAt == nil)
    }

    @Test func aConclusivelyMissingTransactionKeepsTheCardButPermitsRetry() throws {
        let attempted = try GiftCardLedger.setFundingAttemptedAt([card()], id: Self.id, at: Self.later)

        let retryable = try #require(try GiftCardLedger.markFundingNotCreated(attempted, id: Self.id, at: Self.latest).first)

        #expect(retryable.isFundingRetryable)
        #expect(retryable.hasFundingHistory)
        #expect(!retryable.hasFundingAttempt)
        #expect(!retryable.isUnsharedFunds)
        #expect(retryable.fundingTxid == nil)
        #expect(retryable.fundingFailures.first?.reason == .noTransaction)
        #expect(retryable.fundingFailures.count == 1)
    }

    @Test func anExpiredSharedCardRemainsTheSameRetryableBearerCard() throws {
        let shared = try #require(try GiftCardLedger.markShared(try submitted(), id: Self.id, at: Self.later).first)

        let retryable = try #require(
            try GiftCardLedger.markFundingExpired([shared], id: Self.id, fundingTxids: [Self.txid], at: Self.latest).first
        )

        #expect(retryable.id == Self.id)
        #expect(retryable.address == shared.address)
        #expect(retryable.mnemonic == shared.mnemonic)
        #expect(retryable.status == .shared)
        #expect(retryable.isFundingRetryable)
        #expect(retryable.fundingFailures.first?.transactionId == Self.txid)
        #expect(try GiftLinkCodec.encode(shared.toLinkPayload()) == (try GiftLinkCodec.encode(retryable.toLinkPayload())))
    }

    @Test func retryStartsOnTheSameCardAndPreservesTerminalTransactionHistory() throws {
        let expired = try #require(
            try GiftCardLedger.markFundingExpired(try submitted(), id: Self.id, fundingTxids: [Self.txid], at: Self.later).first
        )

        let retry = try #require(try GiftCardLedger.setFundingAttemptedAt([expired], id: Self.id, at: Self.latest).first)

        #expect(retry.id == Self.id)
        #expect(retry.address == expired.address)
        #expect(retry.mnemonic == expired.mnemonic)
        #expect(retry.fundingFailures.first?.transactionId == Self.txid)
        #expect(retry.hasFundingAttempt)
        #expect(!retry.isFundingRetryable)
    }

    @Test func multipleExpiredRetriesRetainEveryHistoricalTransactionId() throws {
        let first = try GiftCardLedger.markFundingExpired(try submitted(), id: Self.id, fundingTxids: [Self.txid], at: Self.later)
        let secondAttempt = try GiftCardLedger.setFundingAttemptedAt(first, id: Self.id, at: Self.latest)
        let secondCreated = try GiftCardLedger.recordFundingCreated(secondAttempt, id: Self.id, fundingTxid: Self.otherTxid, at: Self.latest)

        let retryable = try #require(
            try GiftCardLedger.markFundingExpired(secondCreated, id: Self.id, fundingTxids: [Self.otherTxid], at: Self.latest).first
        )

        #expect(retryable.fundingFailures.map(\.transactionId) == [Self.txid, Self.otherTxid])
    }

    @Test func replacesExpiredEvidenceWithOneActiveRecoveredTransactionAtomically() throws {
        let created = try GiftCardLedger.recordFundingCreated(
            try GiftCardLedger.setFundingAttemptedAt([card()], id: Self.id, at: Self.later),
            id: Self.id,
            fundingTxid: Self.txid,
            at: Self.later
        )

        let replaced = try #require(
            try GiftCardLedger.replaceExpiredFunding(
                created,
                id: Self.id,
                expiredFundingTxids: [Self.txid],
                activeFundingTxid: Self.otherTxid,
                at: Self.latest
            ).first
        )

        #expect(replaced.fundingTxid == Self.otherTxid)
        #expect(replaced.fundingFailures.first?.transactionId == Self.txid)
        #expect(replaced.fundingFailures.count == 1)
        #expect(replaced.hasFundingAttempt)
    }

    @Test func expiredFailureRequiresATransactionId() {
        #expect(throws: GiftRecordInvariantViolation.self) {
            try GiftFundingFailure(reason: .expired, attemptedAt: Self.later, detectedAt: Self.latest)
        }
    }

    @Test func minedCardRequiresATransactionId() {
        #expect(throws: GiftRecordInvariantViolation.self) {
            try self.card(status: .funded)
        }
        #expect(throws: GiftRecordInvariantViolation.self) {
            try self.card(minedAt: Self.later)
        }
    }

    @Test func aRetryCannotReactivateATransactionFromTerminalHistory() throws {
        let failure = try GiftFundingFailure(reason: .expired, attemptedAt: Self.later, transactionId: Self.txid, detectedAt: Self.latest)
        let attempted = try GiftCardLedger.setFundingAttemptedAt(
            [try card(fundingFailures: [failure])],
            id: Self.id,
            at: Self.latest
        )

        #expect(throws: GiftCardTransitionError.self) {
            try GiftCardLedger.recordFundingCreated(attempted, id: Self.id, fundingTxid: Self.txid, at: Self.latest)
        }
    }

    @Test func keepsTheMnemonicOutOfDescriptions() throws {
        let card = try card()

        #expect(!card.description.contains(Self.mnemonic))
        #expect(!"\(card)".contains(Self.mnemonic))
    }

    @Test func recordsACheckWithoutMovingTheCard() throws {
        let shared = try GiftCardLedger.markShared(
            try GiftCardLedger.markFunded([card()], id: Self.id, fundingTxid: Self.txid, at: Self.later),
            id: Self.id,
            at: Self.later
        )

        let checked = try #require(try GiftCardLedger.recordChecked(shared, id: Self.id, at: Self.latest).first)

        // The only new fact is when we last confirmed the funds were still there.
        #expect(checked.lastCheckedAt == Self.latest)
        #expect(checked.status == .shared)
        #expect(checked.fundingTxid == Self.txid)
    }

    @Test func marksASharedCardCollected() throws {
        let cards = [try card(status: .shared, txid: Self.txid)]

        let claimed = try #require(try GiftCardLedger.markClaimed(cards, id: Self.id, at: Self.later).first)

        #expect(claimed.status == .claimed)
    }

    @Test func settlingACardRecordsThatItsFundingMustHaveMined() throws {
        let cards = [try card(status: .shared, txid: Self.txid)]

        let claimed = try #require(try GiftCardLedger.markClaimed(cards, id: Self.id, at: Self.later).first)

        // An emptied wallet cannot have been emptied before it was filled, so the observation
        // backfills the confirmation nothing got round to recording.
        #expect(claimed.fundingMinedAt == Self.later)
    }

    @Test func refusesToMarkAnUnfundedCardCollected() throws {
        // An empty wallet on a card that was never funded means nobody took anything.
        #expect(throws: GiftCardTransitionError.self) {
            try GiftCardLedger.markClaimed([self.card()], id: Self.id, at: Self.later)
        }
    }

    @Test func aCollectedCardNoLongerHoldsUnsharedFunds() throws {
        let cards = try GiftCardLedger.markClaimed([card(status: .shared, txid: Self.txid)], id: Self.id, at: Self.later)

        // Blocking a wallet reset over money somebody already took would be a false alarm.
        #expect(!GiftCardLedger.hasUnsharedFunds(cards))
    }

    @Test func aCollectedCardCannotRegressToShared() throws {
        let cards = try GiftCardLedger.markClaimed([card(status: .shared, txid: Self.txid)], id: Self.id, at: Self.later)

        let reshared = try #require(try GiftCardLedger.markShared(cards, id: Self.id, at: Self.latest).first)

        #expect(reshared.status == .claimed)
    }

    @Test func mintingSupersedesADraftNothingWasEverSentTo() throws {
        let abandoned = try GiftCardLedger.add([], card: card())

        let cards = try GiftCardLedger.add(abandoned, card: card(id: Self.otherId))

        // Its address never saw a transaction, so the seed unlocks nothing and keeping the record
        // only grows the one blob every mutation rewrites.
        #expect(cards.map(\.id) == [Self.otherId])
    }

    @Test func mintingNeverDiscardsADraftWhoseBroadcastWasStarted() throws {
        let flagged = try GiftCardLedger.setFundingAttemptedAt([card()], id: Self.id, at: Self.later)

        let cards = try GiftCardLedger.add(flagged, card: card(id: Self.otherId))

        // The money may already have left, and this record is the only route back to it.
        #expect(cards.map(\.id) == [Self.id, Self.otherId])
    }

    @Test func mintingNeverDiscardsACardThatReachedAnyLaterStatus() throws {
        let kept = [try card(id: "funded", status: .funded, txid: Self.txid)]

        let cards = try GiftCardLedger.add(kept, card: card())

        #expect(cards.map(\.id) == ["funded", Self.id])
    }

    /// One draft carrying a submitted funding txid — the state a card shares from.
    private func submitted() throws -> [StoredGiftCard] {
        try GiftCardLedger.recordFundingSubmitted([card()], id: Self.id, fundingTxid: Self.txid, at: Self.later)
    }

    private func card(
        id: String = id,
        amount: Int64 = 100_000_000,
        status: GiftCardStatus = .draft,
        txid: String? = nil,
        attemptedAt: String? = nil,
        minedAt: String? = nil,
        fundingFailures: [GiftFundingFailure] = []
    ) throws -> StoredGiftCard {
        try StoredGiftCard(
            id: id,
            network: "main",
            address: "u1exampleunifiedaddressforgiftcardtests",
            mnemonic: Self.mnemonic,
            amountZatoshi: amount,
            birthdayHeight: 2_800_000,
            sourceAccountUuid: Self.account,
            createdAt: Self.created,
            updatedAt: Self.created,
            status: status,
            fundingTxid: txid,
            fundingAttemptedAt: attemptedAt,
            fundingMinedAt: minedAt,
            fundingFailures: fundingFailures
        )
    }
}
