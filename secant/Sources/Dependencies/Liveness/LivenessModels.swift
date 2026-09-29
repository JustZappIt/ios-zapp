// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
@preconcurrency import ZappOfframp

struct LivenessStandingModel: Equatable, Sendable {
    let isVerified: Bool
    /// Per-order limit through the integrator; zero until verified.
    let limitMicros: String
    /// What verifying is worth to a wallet that has not yet.
    let tierCapMicros: String
}

enum LivenessStatusModel: Equatable, Sendable {
    case preparing
    case ready(widgetURL: String, expiresInSeconds: Int)
    case verifying
    case submitting
    case done(LivenessStandingModel)
    case identityDone(ReputationSummaryModel)
    case failed(LivenessFailureModel)
}

enum LivenessFailureModel: String, Equatable, Sendable {
    case unavailable = "Unavailable"
    case notPassed = "NotPassed"
    case alreadyVerified = "AlreadyVerified"
    case notConfigured = "NotConfigured"
    case notLive = "NotLive"
    case alreadyClaimed = "AlreadyClaimed"
    case expired = "Expired"
    case cancelled = "Cancelled"
    case rejected = "Rejected"
    case sponsorshipUnavailable = "SponsorshipUnavailable"
    case network = "Network"
    case busy = "Busy"
    case unknown
}

/// The widget's redirect: a one-time `code` on success, an `error` otherwise, our own `state` beside a code.
struct LivenessReturnModel: Equatable, Sendable {
    let code: String?
    let error: String?
    let state: String?
    var check: IdentityCheckModel = .liveness

    var currencyCode: String? {
        guard let state, let currency = IdentityReturn.companion.currencyFromState(state: state) else { return nil }
        return currency.code
    }
}

extension LivenessStatusModel {
    init(_ value: AppleIdentityStatus) {
        switch onEnum(of: value) {
        case .preparing:
            self = .preparing
        case let .ready(ready):
            self = .ready(widgetURL: ready.widgetUrl, expiresInSeconds: 1800)
        case .verifying:
            self = .verifying
        case .submitting:
            self = .submitting
        case let .done(done):
            self = .identityDone(ReputationSummaryModel(done.summary))
        case let .failed(failed):
            self = .failed(LivenessFailureModel(rawValue: failed.reason) ?? .unknown)
        }
    }
}

enum IdentityCheckModel: String, Equatable, Sendable, CaseIterable {
    case liveness = "Liveness"
    case passport = "Passport"

    var kotlin: IdentityCheck { self == .liveness ? .liveness : .passport }
}
