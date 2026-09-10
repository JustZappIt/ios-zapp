// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
@preconcurrency import ZappOfframp

/// One address's standing with the exchange, as the chain reports it. Every figure here is read,
/// never computed: the buy limit is the Diamond's own number, and deriving it from `points` would
/// put a second, disagreeing answer in front of the user.
struct ReputationSummaryModel: Equatable, Sendable {
    let currencyCode: String
    let points: String
    /// The ReputationManager's own blacklist flag. Terminal: verifying will not clear it.
    let isBlocked: Bool
    /// A cold wallet's buy limit is $0 and it cannot place a BUY of any size. Cashing out is never
    /// gated by reputation, so this must never read as a wallet-wide lock.
    let canBuy: Bool
    let isAtCeiling: Bool
    let buyLimitMicros: String
    let maxBuyLimitMicros: String
    let platforms: [ReputationPlatformModel]

    var verified: [ReputationPlatformModel] { platforms.filter(\.isVerified) }
}

struct ReputationPlatformModel: Equatable, Sendable, Identifiable {
    /// The routing key, and what the Reclaim return link carries.
    let id: String
    /// The brand's own spelling, as the contract holds it. Never translated.
    let name: String
    let awardPoints: String
    let isVerified: Bool
    /// The provider's own age rule. A too-new account comes back as a *successful* proof carrying
    /// nothing, so the row says so before the user spends five minutes finding out.
    let requiresMatureAccount: Bool
    /// What verifying this account would actually add to the buy limit, clamped to the headroom
    /// that is left. Nil means say nothing — never zero.
    let limitGainMicros: String?
}

enum ReclaimStatusModel: Equatable, Sendable {
    case preparing
    /// The short link Reclaim minted for this session. It resolves to the Verifier app when it is
    /// installed and to Safari otherwise.
    case ready(requestURL: String)
    case verifying
    case submitting
    case done(ReputationSummaryModel)
    case failed(ReclaimFailureModel)
}

/// Each of these needs its own sentence; none of them is "something went wrong". Three different
/// contract reverts mean "one account, one wallet" and all arrive as `alreadyVerifiedElsewhere`.
enum ReclaimFailureModel: String, Equatable, Sendable {
    case notConfigured = "NotConfigured"
    case criteriaNotMet = "CriteriaNotMet"
    case proofGenerationFailed = "ProofGenerationFailed"
    case sessionExpired = "SessionExpired"
    case alreadyVerifiedElsewhere = "AlreadyVerifiedElsewhere"
    case addressMismatch = "AddressMismatch"
    case verificationRejected = "VerificationRejected"
    case sponsorshipUnavailable = "SponsorshipUnavailable"
    case network = "Network"
    /// The facade refused to start a second session while one is live.
    case busy = "Busy"
    case unknown
}

/// The platform ids a return link may name. Read from the framework's own table so the two can
/// never drift: a platform added on chain arrives here with the next vendor, not with a patch.
enum SocialPlatformID {
    static let all: [String] = SocialPlatform.allCases.map(\.name)
    static let binance = SocialPlatform.binance.name

    static func match(_ raw: String?) -> String? {
        guard let raw else { return nil }
        return all.first { $0.caseInsensitiveCompare(raw) == .orderedSame }
    }
}

/// The corridors the exchange trades, likewise read from the framework.
enum ReputationCorridor {
    static let all: [String] = CurrencyCode.allCases.map(\.code)
    static let inr = CurrencyCode.inr.code

    static func match(_ raw: String?) -> String? {
        guard let raw else { return nil }
        return all.first { $0.caseInsensitiveCompare(raw) == .orderedSame }
    }
}
