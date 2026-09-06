// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

/// A gift this wallet is collecting, and — until its claim is final — the only way back to it.
///
/// A broadcast that reached the mempool can expire or reorg. The link is written before broadcast,
/// kept with the isolated wallet database, and dropped only after SDK finality. `address` is the
/// identity, so one link cannot produce two receipts.
struct ReceivedGift: Codable, Equatable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case address
        case network
        case amountZatoshi
        case claimedAt
        case destinationAddress
        case destinationAccountUuid
        case claimTxids
        case claimSubmissionAttemptedAt
        case message
        case claimLink
        case isFinalized
        case isClaimedElsewhere
    }

    let address: String
    let network: String
    let amountZatoshi: Int64
    let claimedAt: String
    var destinationAddress: String?
    /// Account that received the claim, persisted so confirmation never follows UI selection.
    var destinationAccountUuid: String?
    var claimTxids: [String]
    /// Written at the irreversible boundary, before entering create-and-submit.
    var claimSubmissionAttemptedAt: String?
    let message: String?
    /// The bearer link, held until every `claimTxids` transaction reaches SDK finality.
    var claimLink: GiftLinkPayload?
    /// Durable cleanup checkpoint written before the isolated database is deleted.
    var isFinalized: Bool
    /// A scan found somebody else's final spend of this card. Separate from `claimTxids`, which
    /// records only what *this* wallet submitted, so without this flag the answer would have to be
    /// rediscovered by a full rescan every time the link is opened again.
    var isClaimedElsewhere: Bool

    init(
        address: String,
        network: String,
        amountZatoshi: Int64,
        claimedAt: String,
        destinationAddress: String? = nil,
        destinationAccountUuid: String? = nil,
        claimTxids: [String] = [],
        claimSubmissionAttemptedAt: String? = nil,
        message: String? = nil,
        claimLink: GiftLinkPayload? = nil,
        isFinalized: Bool = false,
        isClaimedElsewhere: Bool = false
    ) throws {
        self.address = address
        self.network = network
        self.amountZatoshi = amountZatoshi
        self.claimedAt = claimedAt
        self.destinationAddress = destinationAddress
        self.destinationAccountUuid = destinationAccountUuid
        self.claimTxids = claimTxids
        self.claimSubmissionAttemptedAt = claimSubmissionAttemptedAt
        self.message = message
        self.claimLink = claimLink
        self.isFinalized = isFinalized
        self.isClaimedElsewhere = isClaimedElsewhere
        try validate()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.address = try container.decode(String.self, forKey: .address)
        self.network = try container.decode(String.self, forKey: .network)
        self.amountZatoshi = try container.decode(Int64.self, forKey: .amountZatoshi)
        self.claimedAt = try container.decode(String.self, forKey: .claimedAt)
        self.destinationAddress = try container.decodeIfPresent(String.self, forKey: .destinationAddress)
        self.destinationAccountUuid = try container.decodeIfPresent(String.self, forKey: .destinationAccountUuid)
        self.claimTxids = try container.decodeIfPresent([String].self, forKey: .claimTxids) ?? []
        self.claimSubmissionAttemptedAt = try container.decodeIfPresent(String.self, forKey: .claimSubmissionAttemptedAt)
        self.message = try container.decodeIfPresent(String.self, forKey: .message)
        self.claimLink = try container.decodeIfPresent(GiftLinkPayload.self, forKey: .claimLink)
        self.isFinalized = try container.decodeIfPresent(Bool.self, forKey: .isFinalized) ?? false
        self.isClaimedElsewhere = try container.decodeIfPresent(Bool.self, forKey: .isClaimedElsewhere) ?? false
        try validate()
    }

    /// The claim is final, so nothing can need the link again.
    var isSettled: Bool {
        claimLink == nil
    }

    /// The custody boundary. A receipt is written before the scan starts, so one exists for every
    /// card this wallet merely *looked* at, and none of those hold recovery material: nothing was
    /// created, and the link inside is a copy of one the sender still holds. Only past this
    /// boundary may a receipt keep a screen reopening or a wallet undeletable.
    var hasClaimAttempt: Bool {
        claimSubmissionAttemptedAt != nil || !claimTxids.isEmpty
    }

    /// Unfinished *and* holding recovery material — the only receipts anything should act on.
    var isUnsettledClaim: Bool {
        !isSettled && hasClaimAttempt
    }

    private func validate() throws {
        // A link for another network cannot retry this one. The store reads it as corrupt.
        guard claimLink == nil || claimLink?.network == network else {
            throw GiftRecordInvariantViolation(message: "Received gift link does not match its record")
        }
    }
}

// The sender's words, an amount, and — while unsettled — the mnemonic.
extension ReceivedGift: CustomStringConvertible, CustomDebugStringConvertible {
    var description: String { "ReceivedGift(network=\(network), redacted)" }
    var debugDescription: String { description }
}

extension Array where Element == ReceivedGift {
    /// Newest first, one receipt per card, and never regresses durable recovery state.
    func recording(_ gift: ReceivedGift) -> [ReceivedGift] {
        let current = first { $0.address == gift.address }
        let merged: ReceivedGift
        switch current {
        case .none:
            merged = gift

        case .some(let current) where current.isSettled:
            merged = current

        case .some(let current):
            let startsNewSubmission =
                gift.claimSubmissionAttemptedAt != nil
                    && gift.claimSubmissionAttemptedAt != current.claimSubmissionAttemptedAt
                    && gift.claimTxids.isEmpty
            var next = gift
            // An unsettled claim stays pinned to the account/address that received its first
            // attempt. Following UI selection on a retry makes confirmation look in the wrong
            // account and can split one card's transactions across accounts.
            next.destinationAddress = current.destinationAddress ?? gift.destinationAddress
            next.destinationAccountUuid = current.destinationAddress != nil
                ? current.destinationAccountUuid
                : gift.destinationAccountUuid
            next.claimTxids = startsNewSubmission ? [] : mergeClaimTxids(current.claimTxids, gift.claimTxids)
            next.claimSubmissionAttemptedAt = gift.claimSubmissionAttemptedAt ?? current.claimSubmissionAttemptedAt
            next.claimLink = current.claimLink ?? gift.claimLink
            next.isFinalized = startsNewSubmission ? false : (current.isFinalized || gift.isFinalized)
            // Never cleared by a new submission: the card is empty whatever this wallet does.
            next.isClaimedElsewhere = current.isClaimedElsewhere || gift.isClaimedElsewhere
            merged = next
        }
        return [merged] + filter { $0.address != gift.address }
    }

    /// One-way, and a no-op if absent.
    func settling(_ address: String) -> [ReceivedGift] {
        map { gift in
            guard gift.address == address else { return gift }
            var next = gift
            next.claimLink = nil
            return next
        }
    }

    func finalizing(_ address: String) -> [ReceivedGift] {
        map { gift in
            guard gift.address == address else { return gift }
            var next = gift
            next.isFinalized = true
            return next
        }
    }

    /// Its own transition rather than part of `recording` because it is written after `settling`,
    /// and a settled receipt deliberately refuses further merges.
    func markingClaimedElsewhere(_ address: String) -> [ReceivedGift] {
        map { gift in
            guard gift.address == address else { return gift }
            var next = gift
            next.isClaimedElsewhere = true
            return next
        }
    }

    /// The only discard over this store, and the one that cannot lose anything: `hasClaimAttempt`
    /// is false exactly when no transaction was created and none was broadcast, so the record
    /// describes a card this wallet read and nothing more.
    ///
    /// Deliberately narrow. A settled receipt is history, a foreign-claim receipt is a terminal
    /// answer worth keeping so the link need not be rescanned, and anything past the boundary is
    /// custody.
    func discardingUnstarted(_ address: String) -> [ReceivedGift] {
        filter { !($0.address == address && !$0.hasClaimAttempt && !$0.isClaimedElsewhere && !$0.isSettled) }
    }

    private func mergeClaimTxids(_ current: [String], _ incoming: [String]) -> [String] {
        if incoming.isEmpty { return current }
        if current.isEmpty { return incoming }
        if incoming.contains(where: current.contains) {
            var seen = Set<String>()
            return (current + incoming).filter { seen.insert($0).inserted }
        }
        return incoming
    }
}
