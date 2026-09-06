// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
@testable import zodl_internal

@Suite struct ReceivedGiftTests {
    private static let payload = GiftLinkPayload(
        version: 1,
        network: "main",
        amountZatoshi: "100000000",
        mnemonic: "test mnemonic",
        birthdayHeight: 1,
        createdAt: "2026-08-23T00:00:00Z"
    )

    @Test func preparedWriteCannotEraseSubmittedTxids() throws {
        let submitted = try receipt(claimTxids: ["tx-1"])
        let prepared = try receipt(claimTxids: [])

        #expect([submitted].recording(prepared).first?.claimTxids == ["tx-1"])
    }

    @Test func staleWriteCannotRegressFinalReceipt() throws {
        let settled = try receipt(claimLink: nil, isFinalized: true)

        let result = try #require([settled].recording(try receipt()).first)

        #expect(result.isSettled)
        #expect(result.claimLink == nil)
    }

    @Test func transactionsFromTheSameAttemptAreMerged() throws {
        let result = [try receipt(claimTxids: ["tx-1"])]
            .recording(try receipt(claimTxids: ["tx-1", "tx-2"]))

        #expect(result.first?.claimTxids == ["tx-1", "tx-2"])
    }

    @Test func aRetryReplacesExpiredAttemptTxids() throws {
        let result = [try receipt(claimTxids: ["expired"])].recording(try receipt(claimTxids: ["retry"]))

        #expect(result.first?.claimTxids == ["retry"])
    }

    @Test func newSubmissionMarkerClearsExpiredIdsAndStaleFinalizationCheckpoint() throws {
        let previous = try receipt(
            claimTxids: ["expired"],
            claimSubmissionAttemptedAt: "attempt-1",
            isFinalized: true
        )

        let result = try #require(
            [previous].recording(try receipt(claimTxids: [], claimSubmissionAttemptedAt: "attempt-2")).first
        )

        #expect(result.claimTxids.isEmpty)
        #expect(result.isFinalized == false)
    }

    @Test func unsettledRetryRemainsPinnedToItsOriginalDestination() throws {
        let previous = try receipt(
            destinationAddress: "original-address",
            destinationAccountUuid: "original-account"
        )

        let result = try #require(
            [previous].recording(
                try receipt(
                    destinationAddress: "newly-selected-address",
                    destinationAccountUuid: "newly-selected-account"
                )
            ).first
        )

        #expect(result.destinationAddress == "original-address")
        #expect(result.destinationAccountUuid == "original-account")
    }

    @Test func aReceiptForACardThisWalletOnlyReadHoldsNoRecoveryMaterial() throws {
        let read = try receipt(claimTxids: [], claimSubmissionAttemptedAt: nil)

        #expect(!read.hasClaimAttempt)
        // Nothing was created, so there is nothing to recover.
        #expect(!read.isUnsettledClaim)
    }

    @Test func theSubmissionMarkerAloneMakesAReceiptCustody() throws {
        // Past the marker the transaction may exist whatever came back, so the link is the only
        // route to a card this wallet may already have spent from.
        let started = try receipt(claimTxids: [], claimSubmissionAttemptedAt: "2026-08-23T00:01:00Z")

        #expect(started.hasClaimAttempt)
        #expect(started.isUnsettledClaim)
    }

    @Test func aSettledReceiptIsNoLongerUnsettledWork() throws {
        #expect(try receipt(claimTxids: ["tx-1"], claimLink: nil).isUnsettledClaim == false)
    }

    @Test func discardsOnlyAReceiptThatNeverStartedAClaim() throws {
        let read = try receipt(claimTxids: [])

        #expect([read].discardingUnstarted("card-address").isEmpty)
    }

    @Test func discardLeavesEveryReceiptThatCouldStillNeedItsLink() throws {
        let submitted = try receipt(claimTxids: ["tx-1"])
        let started = try receipt(claimTxids: [], claimSubmissionAttemptedAt: "2026-08-23T00:01:00Z")
        let settled = try receipt(claimTxids: ["tx-1"], claimLink: nil)
        var elsewhere = try receipt(claimTxids: [])
        elsewhere.isClaimedElsewhere = true

        for kept in [submitted, started, settled, elsewhere] {
            #expect(
                [kept].discardingUnstarted("card-address") == [kept],
                """
                a receipt with claimTxids=\(kept.claimTxids), marker=\(String(describing: kept.claimSubmissionAttemptedAt)), \
                settled=\(kept.isSettled), elsewhere=\(kept.isClaimedElsewhere) must survive a discard
                """
            )
        }
    }

    @Test func discardLeavesOtherCardsAlone() throws {
        let other = try receipt(address: "another-card", claimTxids: [])

        #expect([other].discardingUnstarted("card-address") == [other])
    }

    @Test func aLinkForAnotherNetworkReadsAsCorrupt() {
        #expect(throws: GiftRecordInvariantViolation.self) {
            try self.receipt(network: "test")
        }
    }

    @Test func keepsTheLinkOutOfDescriptions() throws {
        let receipt = try receipt()

        #expect(!receipt.description.contains("test mnemonic"))
        #expect(!"\(receipt)".contains("test mnemonic"))
        #expect(receipt.description.contains("redacted"))
    }

    private func receipt(
        address: String = "card-address",
        network: String = "main",
        claimTxids: [String] = [],
        claimSubmissionAttemptedAt: String? = nil,
        claimLink: GiftLinkPayload? = payload,
        isFinalized: Bool = false,
        destinationAddress: String = "wallet-address",
        destinationAccountUuid: String? = nil
    ) throws -> ReceivedGift {
        try ReceivedGift(
            address: address,
            network: network,
            amountZatoshi: 100_000_000,
            claimedAt: "2026-08-23T00:00:00Z",
            destinationAddress: destinationAddress,
            destinationAccountUuid: destinationAccountUuid,
            claimTxids: claimTxids,
            claimSubmissionAttemptedAt: claimSubmissionAttemptedAt,
            claimLink: claimLink,
            isFinalized: isFinalized
        )
    }
}
