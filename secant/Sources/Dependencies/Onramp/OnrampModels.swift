// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
@preconcurrency import ZappOfframp

enum OnrampDestinationModel: String, Equatable, Sendable {
    case zcash = "ZCASH"
    case base = "BASE"
}

enum OnrampPhaseModel: Equatable, Sendable {
    case placing
    case awaitingMerchant
    case awaitingPayment
    case confirmingPaid
    case awaitingSettlement
    case completed
    case expired
    case cancelled
    case failed
    case unknown(String)

    init(_ value: String) {
        switch value.uppercased() {
        case "PLACING": self = .placing
        case "AWAITING_MERCHANT": self = .awaitingMerchant
        case "AWAITING_PAYMENT": self = .awaitingPayment
        case "CONFIRMING_PAID": self = .confirmingPaid
        case "AWAITING_SETTLEMENT": self = .awaitingSettlement
        case "COMPLETED": self = .completed
        case "EXPIRED": self = .expired
        case "CANCELLED": self = .cancelled
        case "FAILED": self = .failed
        default: self = .unknown(value)
        }
    }
}

enum OnrampFailureCodeModel: String, Equatable, Sendable {
    case badRequest = "BAD_REQUEST"
    case unauthenticated = "UNAUTHENTICATED"
    case nonceInvalid = "NONCE_INVALID"
    case recipientNotAllowed = "RECIPIENT_NOT_ALLOWED"
    case routeDisabled = "ROUTE_DISABLED"
    case orderNotFound = "ORDER_NOT_FOUND"
    case wrongPhase = "WRONG_PHASE"
    case quoteExpired = "QUOTE_EXPIRED"
    case capExceeded = "CAP_EXCEEDED"
    case screeningRejected = "SCREENING_REJECTED"
    case upstreamFailed = "UPSTREAM_FAILED"
    case operatorUnavailable = "OPERATOR_UNAVAILABLE"
    case noMerchant = "NO_MERCHANT"
    case orderExpired = "ORDER_EXPIRED"
    case networkUnavailable = "NETWORK_UNAVAILABLE"
    case dailyLimitExceeded = "DAILY_LIMIT_EXCEEDED"
    case volumeLimitExceeded = "VOLUME_LIMIT_EXCEEDED"
    case userBlocked = "USER_BLACKLISTED"
    /// Fiat has left the user's account and the merchant's leg is still outstanding: paid, alive.
    case settlementPending = "SETTLEMENT_PENDING"
    case unknown = "UNKNOWN"

    var leavesOrderAlive: Bool {
        self == .upstreamFailed || self == .operatorUnavailable || self == .networkUnavailable || self == .settlementPending
    }
}

struct OnrampLimitsModel: Equatable, Sendable {
    let enabled: Bool
    let currencyCode: String
    let minimumFiatMicros: String
    let maximumFiatMicros: String
    let dailyFiatMicros: String
}

struct OnrampQuoteModel: Equatable, Sendable {
    let quoteID: String
    let currencyCode: String
    let fiatMicros: String
    let grossUsdcMicros: String
    let feeUsdcMicros: String
    let netUsdcMicros: String
    let buyPriceMicros: String
    let expiresAt: Date
}

struct OnrampZecEstimateModel: Equatable, Sendable {
    let depositAddress: String
    let zcashRecipient: String
    let deadline: Date
    let outputZec: String
    let inputUsd: String
    let outputUsd: String
    let costBasisPoints: Int
}

/// Stable field identities for direct orders, mirroring offramp-lib's `OnrampPaymentFieldKind`.
/// Android localises them at the display boundary, and so does iOS.
enum OnrampPaymentFieldKind: String, CaseIterable, Equatable, Sendable {
    case phoneNumber = "PHONE_NUMBER"
    case documentID = "DOCUMENT_ID"
    case bank = "BANK"
    case accountNumber = "ACCOUNT_NUMBER"
    case bankName = "BANK_NAME"
    case accountName = "ACCOUNT_NAME"
    case cardNumber = "CARD_NUMBER"
    case accountType = "ACCOUNT_TYPE"
    case cedula = "CEDULA"
    case cci = "CCI"
    case pixKey = "PIX_KEY"
    case paymentAlias = "PAYMENT_ALIAS"
}

struct OnrampFieldModel: Equatable, Sendable {
    /// What the bridge sends as the label: a provider's own label when it has one, else the
    /// field kind's name (`AppleOnrampClient.toApple`: `label ?: kind?.name.orEmpty()`).
    let label: String
    let value: String

    /// Nil for a provider label or an unknown kind name: the label is then shown as sent, so a
    /// newer framework never loses a field this build has no translation for.
    var kind: OnrampPaymentFieldKind? { OnrampPaymentFieldKind(rawValue: label) }
}

enum OnrampPaymentInstructionModel: Equatable, Sendable {
    case upi(address: String, payload: String)
    case qr(payload: String)
    /// Per-corridor payee fields, optionally beside a scannable QR (Venezuela, Peru, the
    /// Philippines and Bolivia carry both).
    case fields([OnrampFieldModel], qrPayload: String?)
    case plain(address: String)

    var kind: String {
        switch self {
        case .upi: return "upi"
        case .qr: return "qr"
        case .fields: return "fields"
        case .plain: return "plain"
        }
    }

    var payload: String {
        switch self {
        case .upi(_, let payload), .qr(let payload): return payload
        case .plain(let address): return address
        // The bridge rebuilds a fields instruction from this alone, so the amount check reads
        // the QR's declared amount exactly as Android's `OnrampIntentAmount` does.
        case .fields(_, let qrPayload): return qrPayload ?? ""
        }
    }
}

struct OnrampStatusModel: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case idle
        case quoting
        case placing
        case awaitingMerchant
        case awaitingPayment
        case confirmingPaid
        case awaitingSettlement
        case completed
        case cancelled
        case failed
    }

    let kind: Kind
    let phase: OnrampPhaseModel
    let id: String?
    let orderID: String?
    let failureCode: OnrampFailureCodeModel?
    /// The service's own sentence for a refusal, shown in place of the code's; never branched on.
    let failureDetail: String?
    let instruction: OnrampPaymentInstructionModel?
    let fiatMicros: String?
    let netUsdcMicros: String?
    let recipientAddress: String?
    let paidTransactionHash: String?
    let expiresAt: Date?
    let isTerminal: Bool
}

enum OnrampFundsLocationModel: Equatable, Sendable {
    case baseAccount
    case recipientMismatch
    case transferAmbiguous
    case nearIntent
    case zcashWallet
    case baseRefundConfirmed
    case unknown(String)

    init(_ value: String) {
        switch value.uppercased() {
        case "BASE_ACCOUNT": self = .baseAccount
        case "RECIPIENT_MISMATCH": self = .recipientMismatch
        case "TRANSFER_AMBIGUOUS": self = .transferAmbiguous
        case "NEAR_INTENT": self = .nearIntent
        case "ZCASH_WALLET": self = .zcashWallet
        case "BASE_REFUND_CONFIRMED": self = .baseRefundConfirmed
        default: self = .unknown(value)
        }
    }
}

enum OnrampDeliveryPhaseModel: Equatable, Sendable {
    case fundsOnBase
    case quoting
    case quoteReady
    case transferStarting
    case transferSubmitted
    case awaitingZec
    case delivered
    case refundedToBase
    case needsAttention
    case unknown(String)

    init(_ value: String) {
        switch value.uppercased() {
        case "FUNDS_ON_BASE": self = .fundsOnBase
        case "QUOTING": self = .quoting
        case "QUOTE_READY": self = .quoteReady
        case "TRANSFER_STARTING": self = .transferStarting
        case "TRANSFER_SUBMITTED": self = .transferSubmitted
        case "AWAITING_ZEC": self = .awaitingZec
        case "DELIVERED": self = .delivered
        case "REFUNDED_TO_BASE": self = .refundedToBase
        case "NEEDS_ATTENTION": self = .needsAttention
        default: self = .unknown(value)
        }
    }
}

struct OnrampDeliveryModel: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case preparing
        case submitting
        case awaitingZec
        case delivered
        case refundedToBase
        case failed
    }

    let kind: Kind
    let stage: OnrampDeliveryPhaseModel
    let inputUsdcMicros: String?
    let outputZec: String?
    let refundedUsdcMicros: String?
    let baseAccount: String?
    let baseTransactionHash: String?
    let fundsLocation: OnrampFundsLocationModel?
    let retryable: Bool
    let isTerminal: Bool
    let isSuccess: Bool
}

struct OnrampDeliveryCheckpointModel: Equatable, Sendable {
    let phase: OnrampDeliveryPhaseModel
    let usdcMicros: String
    let baseAccount: String
    let transferStarted: Bool
    let refundedUsdcMicros: String?
    let acceptedCostBasisPoints: Int?
    let fundsLocation: OnrampFundsLocationModel
}

struct OnrampCheckpointModel: Equatable, Sendable {
    let id: String
    let phase: OnrampPhaseModel
    let orderID: String?
    let destination: OnrampDestinationModel
    let zecDelivery: OnrampDeliveryCheckpointModel?
}
