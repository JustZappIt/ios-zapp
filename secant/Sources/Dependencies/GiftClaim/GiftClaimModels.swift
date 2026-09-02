// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
@preconcurrency import ZcashLightClientKit

/// Confirmations a shielded note needs before it can be spent. A gift note arrives on the external
/// scope, so the SDK's default transfer policy gives it the untrusted 10. Mirrored — not read —
/// because the policy fields are internal and nothing on the `Initializer` accepts one.
let giftRequiredConfirmations = 10

/// `fraction` must come from the SDK, never from these heights: the restore path snaps the
/// birthday down to a bundled checkpoint, so a height-derived fraction is negative for the whole
/// scan and then snaps to 100%.
struct GiftClaimProgress: Equatable, Sendable {
    let fraction: Float
    let scannedHeight: BlockHeight?
    let tipHeight: BlockHeight?
}

struct GiftCardHoldings: Equatable, Sendable {
    let available: Zatoshi
    let total: Zatoshi
    /// Whether the card's funding transaction — that one, by txid — has mined.
    ///
    /// "Any mined transaction" is cheaper and wrong: the address is plaintext in the link, so a
    /// *transparent* send from anyone mines into this history while leaving `total` at zero —
    /// indistinguishable from a collected card, and settling is terminal. False means the funding
    /// is still in the mempool, or dropped and possibly yet to mine before it expires.
    let hasFundingArrived: Bool
    /// A claim spend at the SDK's full confirmation threshold.
    var hasFinalClaimSpend = false
    /// A submitted/mined claim that can still expire or reorg.
    var hasPendingClaimSpend = false

    var isEmpty: Bool { total == .zero }

    var isCollected: Bool { hasFundingArrived && hasFinalClaimSpend }
}

struct GiftClaimFinalization: Equatable, Sendable {
    let canSettle: Bool
    let residual: Zatoshi
}

struct GiftClaimResumeEvidence: Equatable, Sendable {
    let claimTxIds: Set<String>
    let submissionWasAttempted: Bool
}

enum GiftClaimOutcome: Equatable, Sendable {
    case claimed(amount: Zatoshi, txIds: [String])

    /// The money is there but not yet spendable — ten confirmations, roughly 12.5 minutes on
    /// mainnet. Its own case because calling a perfectly good card empty here would be a lie, and
    /// `confirmations` lets the wait render as progress rather than a bare "try again".
    case notYetSpendable(available: Zatoshi, total: Zatoshi, confirmations: Int?, requiredConfirmations: Int)

    /// Funding has not arrived, or another holder's pending spend is not final enough for a
    /// verdict.
    case awaitingFunding

    /// A claim spend exists, but this wallet has no durable evidence that it submitted it.
    case alreadyClaimed

    /// The card cannot cover the fee to move its own amount. Distinct from `notYetSpendable`
    /// because waiting does not fix it: a card minted here is funded with the amount *plus* the
    /// claim-fee reserve, so reaching this means the card came from something that does not
    /// reserve the fee, or ZIP 317 now asks for more than the reserve covers.
    case underfunded(available: Zatoshi)

    /// The broadcast did not unambiguously succeed. The isolated database is retained — erasing on
    /// a partial broadcast strands funds, and the SDK needs it for background resubmission.
    case notBroadcast(result: SDKSynchronizerClient.CreateProposedTransactionsResult)
}

/// Why the claim engine could not finish. Each drives different copy and different recipient
/// action; none of them says anything about the card.
enum GiftClaimEngineError: Error, Equatable {
    /// The card's server could not be reached at all, so nothing was learned about the card.
    case unreachable

    /// The isolated synchronizer was stopped and can never reach synced.
    case stopped

    /// The card's scan stopped advancing, so it will never reach synced on its own.
    case scanStalled

    /// The Sapling proving parameters are missing and could not be fetched, so a spend cannot be
    /// built. The ZEC is untouched.
    case paramsUnavailable
}

enum GiftOutgoingClaimDisposition: Equatable {
    case none
    case resume
    case awaitingFinality
    case alreadyClaimed
}

/// The size filter feeding these sets matters: the address is public, so a stranger's dust spend
/// must be neither claim evidence nor collection evidence.
func classifyOutgoingGiftClaim(
    finalTxIds: Set<String>,
    pendingTxIds: Set<String>,
    locallySubmittedTxIds: Set<String>
) -> GiftOutgoingClaimDisposition {
    let outgoingTxIds = finalTxIds.union(pendingTxIds)
    if outgoingTxIds.isEmpty { return .none }
    let resumedTxIds = outgoingTxIds.intersection(locallySubmittedTxIds)
    if !finalTxIds.subtracting(resumedTxIds).isEmpty { return .alreadyClaimed }
    if resumedTxIds.isEmpty { return .awaitingFinality }
    return .resume
}

extension ZcashTransaction.Overview {
    /// `value` is negative for sends.
    var absoluteValue: Zatoshi {
        Zatoshi(abs(value.amount))
    }

    func isFinalClaimSpend(of amount: Zatoshi) -> Bool {
        isSentTransaction && absoluteValue >= amount && state == .confirmed
    }

    func isPendingClaimSpend(of amount: Zatoshi) -> Bool {
        isSentTransaction && absoluteValue >= amount && state == .pending
    }
}

/// The movement half of the stall watchdog, pure so the window arithmetic tests without a clock.
///
/// Either signal counts as movement: the height only lands per batch, the fraction moves within
/// one. Furthest-ever, not last, so a regressing height is a restarting batch, not progress. The
/// window must stay above the gRPC streaming deadline — a whole block-batch download advances
/// nothing.
struct GiftScanStallTracker {
    static let pollIntervalSeconds = 10
    /// 36 idle polls = 6 minutes.
    static let idlePollLimit = 36

    private var furthestHeight: Int64
    private var furthestFraction: Float
    private var idlePolls = 0

    init(height: Int64?, fraction: Float) {
        // Below every real height, so the first one to arrive counts as movement.
        self.furthestHeight = height ?? .min
        self.furthestFraction = fraction
    }

    /// Called once per poll interval. True means the scan will never reach synced on its own.
    mutating func poll(height: Int64?, fraction: Float) -> Bool {
        let height = height ?? .min
        if height > furthestHeight || fraction > furthestFraction {
            furthestHeight = max(furthestHeight, height)
            furthestFraction = max(furthestFraction, fraction)
            idlePolls = 0
            return false
        }
        idlePolls += 1
        return idlePolls >= Self.idlePollLimit
    }
}
