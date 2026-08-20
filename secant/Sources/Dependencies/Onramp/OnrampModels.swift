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
    case unknown = "UNKNOWN"

    var leavesOrderAlive: Bool {
        self == .upstreamFailed || self == .operatorUnavailable || self == .networkUnavailable
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

struct OnrampFieldModel: Equatable, Sendable {
    let label: String
    let value: String
}

enum OnrampPaymentInstructionModel: Equatable, Sendable {
    case upi(address: String, payload: String)
    case qr(payload: String)
    case fields([OnrampFieldModel])
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
        case .fields: return ""
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
