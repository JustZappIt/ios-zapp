// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

/// Localized copy for the protocol's stable codes. Kotlin exports codes, never display strings, so
/// this is the single place they become words — one mapping rather than one per screen, because
/// three surfaces describe the same order and a copy that drifted between them would be read as
/// three different states.
extension PeerDestination {
    /// The rail's own product name. Unbranded by design: the asset catalogue carries no approved
    /// Revolut, Zelle, Chime or Monzo mark, and a substitute glyph would be worse than none.
    static func displayName(for code: String) -> String {
        switch code {
        case "revolut": return String(localizable: .peerDestinationRevolut)
        case "zelle": return String(localizable: .peerDestinationZelle)
        case "chime": return String(localizable: .peerDestinationChime)
        case "monzo": return String(localizable: .peerDestinationMonzo)
        default: return code
        }
    }

    /// What a valid handle looks like on this rail, which differs enough between them that a
    /// generic hint would be wrong on three of the four.
    static func handleHint(for code: String) -> String {
        switch code {
        case "revolut": return String(localizable: .peerHandleHintRevolut)
        case "zelle": return String(localizable: .peerHandleHintZelle)
        case "chime": return String(localizable: .peerHandleHintChime)
        case "monzo": return String(localizable: .peerHandleHintMonzo)
        default: return String(localizable: .peerHandleHintGeneric)
        }
    }

    var displayName: String { Self.displayName(for: code) }
    var handleHint: String { Self.handleHint(for: code) }
    var currencyCodes: [String] { currencies.map(\.code) }
}

extension PeerOrder.Phase {
    var label: String {
        switch self {
        case .waiting: return String(localizable: .peerPhaseWaiting)
        case .buyerPaying: return String(localizable: .peerPhaseBuyerPaying)
        case .partlySold: return String(localizable: .peerPhasePartlySold)
        case .sold: return String(localizable: .peerPhaseSold)
        case .paused: return String(localizable: .peerPhasePaused)
        case .closed: return String(localizable: .peerPhaseClosed)
        }
    }
}

extension PeerBuyerLeg.Outcome {
    var label: String {
        switch self {
        case .paying: return String(localizable: .peerLegPaying)
        case .outOfTime: return String(localizable: .peerLegOutOfTime)
        case .paid: return String(localizable: .peerLegPaid)
        case .backedOut: return String(localizable: .peerLegBackedOut)
        case .timedOut: return String(localizable: .peerLegTimedOut)
        case .unknown: return String(localizable: .peerLegUnknown)
        }
    }
}

extension PeerFailure {
    /// Peer's own message strings are developer-facing — they reference SDK calls and Basescan — so
    /// they stay in bug reports and never reach a user.
    ///
    /// A decoded escrow revert is more specific than the code that carried it: a `removeFunds` that
    /// reverted because a buyer holds the balance is not "we could not create your order".
    var message: String {
        switch escrowRevertBucket ?? code {
        case "INSUFFICIENT_AVAILABLE_FUNDS":
            return String(localizable: .peerFailureInsufficientAvailable)
        case "STALE_DEPOSIT_ID", "ORDER_NOT_FOUND", "INDEXER_UNAVAILABLE":
            return String(localizable: .peerFailureRead)
        case "RAIL_UNAVAILABLE", "UNSUPPORTED_PLATFORM", "CURRENCY_UNAVAILABLE", "UNSUPPORTED_PLATFORM_CURRENCY":
            return String(localizable: .peerFailureRailUnavailable)
        case "PAYEE_REGISTRATION_FAILED", "CURATOR_UNAVAILABLE":
            return String(localizable: .peerFailurePayeeUnconfirmed)
        case "PAYEE_NOT_FOUND_ON_PLATFORM":
            return String(localizable: .peerFailurePayeeNotFound)
        case "INSUFFICIENT_TOKEN_BALANCE":
            return String(localizable: .peerFailureInsufficientBalance)
        case "ACTIVE_INTENT_BLOCKS_WITHDRAWAL":
            return String(localizable: .peerFailureBuyerMidPayment)
        case "NOTHING_TO_WITHDRAW":
            return String(localizable: .peerFailureNothingToWithdraw)
        // The unknown-outcome codes share one message. What matters is that it offers no retry and
        // says plainly that the funds are accounted for even though the app cannot say where.
        case "TRANSACTION_SUBMISSION_UNKNOWN", "TRANSACTION_STATUS_UNKNOWN", "DEPOSIT_RESOLUTION_FAILED",
             "RECOVERY_STATE_UNREADABLE":
            return String(localizable: .peerFailureChecking)
        default:
            return String(localizable: .peerFailureGeneric)
        }
    }
}
