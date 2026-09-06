// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ZcashLightClientKit

/// A stored gift record that breaks its own invariants. The store treats it as corrupt, never as
/// absent.
struct GiftRecordInvariantViolation: Error, Equatable {
    let message: String
}

/// Lifecycle of a locally minted card. Raw-value order is the only legal direction of travel.
enum GiftCardStatus: Int, Codable, Equatable, Comparable {
    /// Key material generated and persisted; nothing on chain yet.
    case draft = 0

    /// The funding transaction has mined. Never set without a txid.
    ///
    /// Not the test for "the money is on the card": sharing is legal from the first broadcast and
    /// the status only climbs, so a card shared before its funding mined never takes this rank.
    /// Collection checks ask `StoredGiftCard.isFundingMined` instead.
    case funded = 1

    /// The link has been handed to the share sheet at least once.
    case shared = 2

    /// A claim spend reached SDK finality. Terminal.
    case claimed = 3

    static func < (lhs: GiftCardStatus, rhs: GiftCardStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Why an earlier funding attempt is conclusively safe to replace.
enum GiftFundingFailureReason: String, Codable, Equatable {
    /// A fully-synced wallet database contained no transaction created by the durable marker.
    case noTransaction

    /// The SDK reported the transaction expired, so consensus will no longer accept it.
    case expired
}

/// Durable evidence for a funding attempt that can no longer put money on the card.
///
/// Failed transaction ids are retained rather than overwritten by a retry, so reconciliation can
/// tell the new active transaction from every expired predecessor.
struct GiftFundingFailure: Codable, Equatable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case reason
        case attemptedAt
        case transactionId
        case detectedAt
    }

    let reason: GiftFundingFailureReason
    let attemptedAt: String?
    let transactionId: String?
    let detectedAt: String

    init(reason: GiftFundingFailureReason, attemptedAt: String?, transactionId: String? = nil, detectedAt: String) throws {
        self.reason = reason
        self.attemptedAt = attemptedAt
        self.transactionId = transactionId
        self.detectedAt = detectedAt
        try validate()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.reason = try container.decode(GiftFundingFailureReason.self, forKey: .reason)
        self.attemptedAt = try container.decodeIfPresent(String.self, forKey: .attemptedAt)
        self.transactionId = try container.decodeIfPresent(String.self, forKey: .transactionId)
        self.detectedAt = try container.decode(String.self, forKey: .detectedAt)
        try validate()
    }

    private func validate() throws {
        try ensure(attemptedAt == nil || attemptedAt?.isBlank == false, "A funding failure attempt timestamp cannot be blank")
        try ensure(!detectedAt.isBlank, "A funding failure detection timestamp is required")
        switch reason {
        case .noTransaction:
            try ensure(transactionId == nil, "A missing-transaction failure cannot identify a transaction")
        case .expired:
            try ensure(transactionId?.isBlank == false, "An expired funding failure requires a transaction id")
        }
    }
}

/// The mutually-exclusive funding state derived from the backward-compatible persisted fields.
/// Typed separately from `StoredGiftCard.status`, which tracks delivery of the link rather than
/// the transaction.
enum GiftFundingLifecycle: Equatable {
    case neverStarted
    case attempting(attemptedAt: String)
    case created(transactionId: String, attemptedAt: String)
    case submitted(transactionId: String)
    case retryable(lastFailure: GiftFundingFailure)
    case mined(transactionId: String)
}

/// The locally persisted half of a card, held in the keychain.
///
/// Custody-critical: the ephemeral seed is random rather than derived from the wallet seed and
/// there is no reclaim, so for an unshared card this record is the only recovery path. `network`
/// and `birthdayHeight` are stored rather than used once at creation because re-sharing rebuilds
/// the link from here.
///
/// Fields are mutable so the ledger's transitions can copy-and-amend, but every mutation must go
/// through `GiftCardLedger` and end in `validate()` — the invariants are money.
struct StoredGiftCard: Codable, Equatable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case network
        case address
        case mnemonic
        case amountZatoshi
        case birthdayHeight
        case sourceAccountUuid
        case createdAt
        case updatedAt
        case status
        case expiresAt
        case message
        case fundingTxid
        case fundingCreatedAt
        case fundingAttemptedAt
        case fundingSubmittedAt
        case fundingMinedAt
        case lastCheckedAt
        case fundingFailures
    }

    let id: String
    let network: String
    let address: String
    let mnemonic: String
    let amountZatoshi: Int64
    let birthdayHeight: Int64
    let sourceAccountUuid: String
    let createdAt: String
    var updatedAt: String
    var status: GiftCardStatus
    let expiresAt: String?
    let message: String?
    var fundingTxid: String?
    /// When `fundingTxid` was created and attached after the durable funding-start marker. Nil on
    /// records written before this phase existed, which is what makes a legacy record carrying a
    /// txid read as submitted rather than merely created.
    var fundingCreatedAt: String?
    /// Set before the SDK creates the funding transaction and cleared once submission is known.
    /// The SDK's background resubmitter can broadcast a locally-created outgoing transaction on
    /// its own, so a record still carrying this marker is a card whose money may or may not have
    /// moved even without a txid.
    var fundingAttemptedAt: String?
    /// A clean lightwalletd acceptance. Nil while submission is unresolved or not yet attempted.
    var fundingSubmittedAt: String?
    /// When the funding transaction was first observed with a block behind it.
    var fundingMinedAt: String?
    /// When the card's own wallet was last scanned and found to still hold its funds. Only a
    /// conclusive look sets it, so it is evidence rather than a record of having tried.
    var lastCheckedAt: String?
    /// Terminal attempts, oldest first. Additive so existing records decode unchanged.
    var fundingFailures: [GiftFundingFailure]

    init(
        id: String,
        network: String,
        address: String,
        mnemonic: String,
        amountZatoshi: Int64,
        birthdayHeight: Int64,
        sourceAccountUuid: String,
        createdAt: String,
        updatedAt: String,
        status: GiftCardStatus,
        expiresAt: String? = nil,
        message: String? = nil,
        fundingTxid: String? = nil,
        fundingCreatedAt: String? = nil,
        fundingAttemptedAt: String? = nil,
        fundingSubmittedAt: String? = nil,
        fundingMinedAt: String? = nil,
        lastCheckedAt: String? = nil,
        fundingFailures: [GiftFundingFailure] = []
    ) throws {
        self.id = id
        self.network = network
        self.address = address
        self.mnemonic = mnemonic
        self.amountZatoshi = amountZatoshi
        self.birthdayHeight = birthdayHeight
        self.sourceAccountUuid = sourceAccountUuid
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.expiresAt = expiresAt
        self.message = message
        self.fundingTxid = fundingTxid
        self.fundingCreatedAt = fundingCreatedAt
        self.fundingAttemptedAt = fundingAttemptedAt
        self.fundingSubmittedAt = fundingSubmittedAt
        self.fundingMinedAt = fundingMinedAt
        self.lastCheckedAt = lastCheckedAt
        self.fundingFailures = fundingFailures
        try validate()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.network = try container.decode(String.self, forKey: .network)
        self.address = try container.decode(String.self, forKey: .address)
        self.mnemonic = try container.decode(String.self, forKey: .mnemonic)
        self.amountZatoshi = try container.decode(Int64.self, forKey: .amountZatoshi)
        self.birthdayHeight = try container.decode(Int64.self, forKey: .birthdayHeight)
        self.sourceAccountUuid = try container.decode(String.self, forKey: .sourceAccountUuid)
        self.createdAt = try container.decode(String.self, forKey: .createdAt)
        self.updatedAt = try container.decode(String.self, forKey: .updatedAt)
        self.status = try container.decode(GiftCardStatus.self, forKey: .status)
        self.expiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt)
        self.message = try container.decodeIfPresent(String.self, forKey: .message)
        self.fundingTxid = try container.decodeIfPresent(String.self, forKey: .fundingTxid)
        self.fundingCreatedAt = try container.decodeIfPresent(String.self, forKey: .fundingCreatedAt)
        self.fundingAttemptedAt = try container.decodeIfPresent(String.self, forKey: .fundingAttemptedAt)
        self.fundingSubmittedAt = try container.decodeIfPresent(String.self, forKey: .fundingSubmittedAt)
        self.fundingMinedAt = try container.decodeIfPresent(String.self, forKey: .fundingMinedAt)
        self.lastCheckedAt = try container.decodeIfPresent(String.self, forKey: .lastCheckedAt)
        self.fundingFailures = try container.decodeIfPresent([GiftFundingFailure].self, forKey: .fundingFailures) ?? []
        try validate()
    }

    var fundingLifecycle: GiftFundingLifecycle {
        if isFundingMined, let fundingTxid {
            return .mined(transactionId: fundingTxid)
        }
        if let fundingAttemptedAt, let fundingTxid {
            return .created(transactionId: fundingTxid, attemptedAt: fundingAttemptedAt)
        }
        if let fundingAttemptedAt {
            return .attempting(attemptedAt: fundingAttemptedAt)
        }
        if let fundingTxid {
            return .submitted(transactionId: fundingTxid)
        }
        if let lastFailure = fundingFailures.last {
            return .retryable(lastFailure: lastFailure)
        }
        return .neverStarted
    }

    /// A terminal failed attempt is deliberately excluded: only `GiftFundingLifecycle.retryable`
    /// may start another transaction.
    var hasFundingAttempt: Bool {
        switch fundingLifecycle {
        case .attempting, .created, .submitted, .mined:
            return true
        case .neverStarted, .retryable:
            return false
        }
    }

    /// Includes failed attempts, which remain visible and recoverable from the saved-card deck.
    var hasFundingHistory: Bool {
        fundingLifecycle != .neverStarted
    }

    var isFundingRetryable: Bool {
        if case .retryable = fundingLifecycle { return true }
        return false
    }

    /// The network accepted the transaction, including legacy records whose txid implied that.
    var isFundingSubmitted: Bool {
        fundingSubmittedAt != nil || (fundingTxid != nil && fundingCreatedAt == nil)
    }

    /// The one state in which discarding a record discards nothing: funding writes
    /// `fundingAttemptedAt` before asking the SDK to create a transaction, so "no funding attempt"
    /// is a durable statement that no transaction can later be submitted or resubmitted.
    var isAbandonedDraft: Bool {
        status == .draft && !hasFundingHistory
    }

    /// The funding is known to have mined, so the card really does hold its money.
    ///
    /// The status fallbacks are for records written before `fundingMinedAt` existed; they are the
    /// only ranks that could have come from a confirmation. A pre-`fundingMinedAt` shared card
    /// therefore reads as unconfirmed and gets picked up by the next reconciliation: one extra
    /// lookup, never a wrong answer.
    var isFundingMined: Bool {
        fundingMinedAt != nil || status == .funded || status == .claimed
    }

    /// This record is the only route back to money that may already have left the sender's wallet.
    /// Keyed on the attempt rather than on `funded` because a broadcast nobody saw the end of has
    /// to be assumed to have landed.
    var isUnsharedFunds: Bool {
        hasFundingAttempt && status < .shared
    }

    func validate() throws {
        try ensure(
            amountZatoshi >= 1 && amountZatoshi <= Zatoshi.Constants.maxZatoshi,
            "A gift card amount must be positive and within the Zcash monetary range"
        )
        try ensure(fundingTxid == nil || fundingTxid?.isBlank == false, "An active funding transaction id cannot be blank")
        let failedTransactionIds = fundingFailures.compactMap(\.transactionId)
        try ensure(
            Set(failedTransactionIds).count == failedTransactionIds.count,
            "A failed funding transaction can only be recorded once"
        )
        if let fundingTxid {
            try ensure(!failedTransactionIds.contains(fundingTxid), "The active funding transaction cannot also be terminal history")
        }
        if isFundingMined {
            try ensure(fundingTxid?.isBlank == false, "A mined gift card requires a funding transaction id")
        }
    }
}

// Same reasoning as GiftLinkPayload's redaction: the mnemonic is the money.
extension StoredGiftCard: CustomStringConvertible, CustomDebugStringConvertible {
    var description: String { "StoredGiftCard(id=\(id), status=\(status), redacted)" }
    var debugDescription: String { description }
}

extension StoredGiftCard {
    func toLinkPayload() -> GiftLinkPayload {
        GiftLinkPayload(
            version: GiftLinkCodec.version,
            network: network,
            amountZatoshi: String(amountZatoshi),
            mnemonic: mnemonic,
            birthdayHeight: birthdayHeight,
            createdAt: createdAt,
            expiresAt: expiresAt,
            message: message
        )
    }
}

extension String {
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private func ensure(_ condition: Bool, _ message: String) throws {
    if !condition { throw GiftRecordInvariantViolation(message: message) }
}
