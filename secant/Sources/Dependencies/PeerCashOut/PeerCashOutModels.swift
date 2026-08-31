// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

/// The Peer maker flow as TCA state sees it.
///
/// Deliberately not the Kotlin types: those are reference objects that are neither `Equatable` nor
/// `Sendable`, so a reducer holding one cannot be diffed or safely crossed between actors. They are
/// converted once, at the dependency boundary, and nothing above it imports `ZappOfframp`.
///
/// The names differ from the protocol's on purpose. `PeerPlatform`, `PeerIntent` and friends are
/// already exported into the Swift namespace by the framework, so reusing them would make every
/// reference in the live client ambiguous.

/// One ungated rail the user can be paid on.
struct PeerDestination: Equatable, Identifiable, Sendable {
    let code: String
    let currencies: [PeerFiatCurrency]
    let defaultCurrencyCodes: [String]
    /// False on Zelle and Chime: the curator cannot confirm those handles, so the user is warned
    /// rather than reassured.
    let validatesHandleLive: Bool
    let offersCurrencyChoice: Bool

    var id: String { code }
}

struct PeerFiatCurrency: Equatable, Identifiable, Sendable {
    let code: String
    let symbol: String
    let precision: Int

    var id: String { code }
}

struct PeerCapabilities: Equatable, Sendable {
    static let unavailable = PeerCapabilities(
        isAvailable: false,
        destinations: [],
        recommendedMinimum: .zero,
        attemptIDByteCount: 16
    )

    /// Peer exists only on Base mainnet. Every Peer surface is gated on this rather than on a
    /// network check of its own, so a build without the rails hides them instead of failing late.
    let isAvailable: Bool
    let destinations: [PeerDestination]
    let recommendedMinimum: UsdcAmount
    let attemptIDByteCount: Int

    func destination(code: String) -> PeerDestination? {
        destinations.first { $0.code == code }
    }
}

/// What the typed handle becomes. A nil `normalized` is a format rejection, which is the only
/// judgement made without asking the curator.
struct PeerHandleCheck: Equatable, Sendable {
    let normalized: String?
    let changedWhatWasTyped: Bool
    let validatesLive: Bool

    var isAcceptable: Bool { normalized != nil }
}

/// The Base account a cash-out spends from. A nil `balance` is a failed read, never an empty
/// account: the amount screen has to refuse an order it cannot check.
struct PeerAccount: Equatable, Sendable {
    let address: String
    let balance: UsdcAmount?
    let explorerURL: URL?
}

/// What the user may actually commit right now: the Base balance less everything earlier attempts
/// have promised and not yet escrowed. An amount is not gone from the account until `createDeposit`
/// is mined, so the raw balance still counts it and three orders would each spend the same coins.
enum PeerSpendableBalance: Equatable, Sendable {
    case loading
    case unavailable
    case ready(balance: UsdcAmount, committed: UsdcAmount)

    var available: UsdcAmount? {
        guard case let .ready(balance, committed) = self else { return nil }
        return balance.subtractingClampedToZero(committed)
    }

    var committed: UsdcAmount? {
        guard case let .ready(_, committed) = self, committed.isPositive else { return nil }
        return committed
    }

    func covers(_ amount: UsdcAmount) -> Bool {
        guard let available else { return false }
        return amount <= available
    }
}

/// Indicative only: the binding rate is whatever the oracle says when a buyer signals an intent.
struct PeerRate: Equatable, Sendable {
    let currencyCode: String
    let fiatPerUsdc: Decimal
    let readAt: Date

    func fiatValue(of amount: UsdcAmount) -> Decimal {
        amount.whole * fiatPerUsdc
    }
}

/// Whether and when this pair actually fills, measured before the user commits anything.
struct PeerMarketReading: Equatable, Sendable {
    enum Verdict: String, Equatable, Sendable {
        /// A range, never a point estimate: the wait is a distribution.
        case band = "BAND"
        /// The pair has data and the data says nobody is buying it right now.
        case littleActivity = "LITTLE_ACTIVITY"
        /// No usable reading. The screen falls back to generic copy rather than inventing one.
        case unknown = "UNKNOWN"
    }

    let currencyCode: String
    let verdict: Verdict
    let averageFill: UsdcAmount?
    let waitLowSeconds: Int
    let waitHighSeconds: Int
    /// The amount asked about is large enough that it fills in pieces over hours. A warning, never
    /// a block: the order is still valid.
    let isOversized: Bool
}

/// An attempt with a durable recovery record, whether or not this process is driving it.
struct PeerAttempt: Equatable, Identifiable, Sendable {
    let id: String
    let destinationCode: String
    let currencyCodes: [String]
    let amount: UsdcAmount
    let createdAt: Date
    let depositID: String?
    /// Whether `amount` is still sitting in the smart account rather than in the escrow.
    let holdsUnescrowedFunds: Bool
}

/// One emission from a running cash-out, withdrawal or matching toggle.
struct PeerProgress: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case idle = "IDLE"
        case validatingPayee = "VALIDATING_PAYEE"
        case funded = "FUNDED"
        case approvingUsdc = "APPROVING_USDC"
        case creatingDeposit = "CREATING_DEPOSIT"
        case orderLive = "ORDER_LIVE"
        case withdrawing = "WITHDRAWING"
        case withdrawn = "WITHDRAWN"
        case failed = "FAILED"
    }

    /// The step the protocol reached, which is what the progress list marks as done or failed.
    enum Step: String, Equatable, Sendable, CaseIterable {
        case initialization = "INITIALIZATION"
        case validatingPayee = "VALIDATING_PAYEE"
        case funding = "FUNDING"
        case approvingUsdc = "APPROVING_USDC"
        case creatingDeposit = "CREATING_DEPOSIT"
        case awaitingBuyer = "AWAITING_BUYER"
        case settling = "SETTLING"
        case withdrawing = "WITHDRAWING"

        /// `initialization` is internal bookkeeping and has no row of its own.
        static let displayed: [Step] = [
            .validatingPayee, .funding, .approvingUsdc, .creatingDeposit, .awaitingBuyer, .settling, .withdrawing
        ]
    }

    /// The attempt, or the deposit id when the operation acts on an order that already exists.
    let subjectID: String
    let kind: Kind
    let step: Step
    let amount: UsdcAmount?
    let txHash: String?
    let depositID: String?
    let order: PeerOrder?
    let failure: PeerFailure?
    let isTerminal: Bool
}

/// A failure carrying the three contracts the money depends on. They are read off the failure and
/// never re-derived from `code`, because getting any of them wrong spends the user's USDC twice.
struct PeerFailure: Equatable, Sendable {
    enum Recovery: Equatable, Sendable {
        /// Look at what this transaction did. The app cannot tell.
        case inspectTransaction(hash: String)
        /// Look at what this account holds. Not even a transaction hash survived.
        case inspectDepositor(address: String)
    }

    let code: String
    let step: PeerProgress.Step
    /// False on the three unknown-outcome codes: a second attempt is how one deposit becomes two,
    /// so those must not even show a retry button.
    let allowsManualRetry: Bool
    /// The failure proves the USDC never left the account. Only a proven negative releases what the
    /// attempt reserved; anything unproven keeps it reserved.
    let nothingEscrowed: Bool
    let recovery: Recovery?
    /// Set when a decoded escrow revert says something more specific than the code that carried it.
    let escrowRevertBucket: String?
}

/// An order as the chain and the indexer describe it. Everything shown about an order comes from
/// here rather than from anything the app remembers, which is what lets it survive process death,
/// reinstall, and a different device on the same seed.
struct PeerOrder: Equatable, Identifiable, Sendable {
    enum Phase: String, Equatable, Sendable {
        case waiting = "WAITING"
        case buyerPaying = "BUYER_PAYING"
        case partlySold = "PARTLY_SOLD"
        case sold = "SOLD"
        case paused = "PAUSED"
        case closed = "CLOSED"
    }

    let depositID: String
    let phase: Phase
    let isFinished: Bool
    let acceptingIntents: Bool
    /// The order at the size it was funded, which no single escrow counter reports.
    let gross: UsdcAmount
    let remaining: UsdcAmount
    let sold: UsdcAmount
    let locked: UsdcAmount
    let withdrawn: UsdcAmount
    /// What a withdrawal can take out once expired intents are pruned.
    let withdrawable: UsdcAmount
    let destinationCode: String?
    let currencyCodes: [String]
    let buyerLegs: [PeerBuyerLeg]
    let offersWithdrawal: Bool
    /// Offered only when live intents hold the whole balance, which is the one case a withdrawal
    /// cannot reach. Otherwise withdrawing is the better action and takes precedence.
    let offersMatchingToggle: Bool
    /// Still valid, but below the floor Peer's orderbook lists, so no buyer is browsing it.
    let isHiddenFromBuyers: Bool
    let openedAt: Date?
    let lastActivityAt: Date?
    let explorerURL: URL?

    var id: String { depositID }
}

/// One buyer's leg of an order.
struct PeerBuyerLeg: Equatable, Identifiable, Sendable {
    enum Outcome: String, Equatable, Sendable {
        case paying = "PAYING"
        case outOfTime = "OUT_OF_TIME"
        case paid = "PAID"
        case backedOut = "BACKED_OUT"
        case timedOut = "TIMED_OUT"
        case unknown = "UNKNOWN"
    }

    let intentHash: String
    let outcome: Outcome
    let amount: UsdcAmount
    let paymentCurrencyCode: String?
    let paymentAmount: String?
    let signalledAt: Date?
    let expiresAt: Date?
    /// Keeps a withdrawal from being offered: the escrow is holding this slice for the buyer.
    let holdsFunds: Bool

    var id: String { intentHash }
}
