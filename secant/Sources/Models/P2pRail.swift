// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

/// The two P2P products the app offers. They are different enough that a shared list without a
/// visible provider would let a user pick "cash out" expecting "scan and pay".
enum P2pProvider: Equatable, Sendable {
    case p2pMe
    case peer
}

/// The P2P rail the primary Pay action opens.
///
/// Peer rails break the old one-currency-per-method mapping — a rail is a destination that offers
/// several settlement currencies — so a selection is identified by a typed id rather than by a
/// currency code.
enum P2pRail: Equatable, Sendable {
    /// p2p.me: scan a merchant's QR and pay them in one currency.
    case scanAndPay(currencyCode: String)
    /// Peer: offer USDC to buyers and receive fiat into your own account.
    case peerCashOut(destinationCode: String)

    /// Served in every deployment, which is what makes it the fallback for a rail that is not.
    static let `default` = P2pRail.scanAndPay(currencyCode: "INR")

    static let scanAndPayPrefix = "p2pme:"
    static let peerPrefix = "peer:"

    /// The stable persistence key, matching Android so one account reads the same on both.
    var id: String {
        switch self {
        case .scanAndPay(let currencyCode): return Self.scanAndPayPrefix + currencyCode
        case .peerCashOut(let destinationCode): return Self.peerPrefix + destinationCode
        }
    }

    var provider: P2pProvider {
        switch self {
        case .scanAndPay: return .p2pMe
        case .peerCashOut: return .peer
        }
    }

    /// The currency a p2p.me flow would use. Peer has no single one — a cash-out can offer several
    /// — so the flows only p2p.me can serve fall back rather than picking one of them arbitrarily.
    var scanAndPayCurrencyCode: String {
        switch self {
        case .scanAndPay(let currencyCode): return currencyCode
        case .peerCashOut: return Self.default.scanAndPayCurrencyCode
        }
    }

    /// An unprefixed value is a selection written before Peer existed, when the preference held a
    /// bare currency code. It resolves rather than resetting the user's choice, and is rewritten in
    /// the new form the next time they save one.
    init?(id: String) {
        if id.hasPrefix(Self.scanAndPayPrefix) {
            self = .scanAndPay(currencyCode: String(id.dropFirst(Self.scanAndPayPrefix.count)))
        } else if id.hasPrefix(Self.peerPrefix) {
            self = .peerCashOut(destinationCode: String(id.dropFirst(Self.peerPrefix.count)))
        } else if !id.isEmpty {
            self = .scanAndPay(currencyCode: id)
        } else {
            return nil
        }
    }
}
