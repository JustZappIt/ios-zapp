// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

/// What both reputation screens render, kept off either reducer: the increase screen uses all of
/// it and owns none of it.
enum ReputationCopy {
    /// Micro-USDC as the exchange's own dollars, trailing zeros stripped — Android's
    /// `Usdc6.toDisplayString(stripTrailingZeros = true)`.
    static func usd(_ micros: String) -> String {
        guard let decimal = Decimal(string: micros) else { return micros }
        return NSDecimalNumber(decimal: decimal / 1_000_000).stringValue
    }

    /// One sentence per case of `ReclaimFailureModel`, which is where the rule is written down.
    static func failureMessage(_ failure: ReclaimFailureModel) -> String {
        switch failure {
        case .notConfigured: return String(localizable: .increaseReputationErrorUnavailable)
        case .criteriaNotMet: return String(localizable: .increaseReputationErrorCriteria)
        case .proofGenerationFailed: return String(localizable: .increaseReputationErrorProof)
        case .sessionExpired: return String(localizable: .increaseReputationErrorExpired)
        case .alreadyVerifiedElsewhere: return String(localizable: .increaseReputationErrorAlreadyUsed)
        case .addressMismatch: return String(localizable: .increaseReputationErrorMismatch)
        case .verificationRejected: return String(localizable: .increaseReputationErrorRejected)
        case .sponsorshipUnavailable: return String(localizable: .increaseReputationErrorGas)
        case .busy: return String(localizable: .increaseReputationErrorBusy)
        case .network, .unknown: return String(localizable: .increaseReputationErrorNetwork)
        }
    }

    static func identityFailureMessage(_ failure: LivenessFailureModel) -> String {
        switch failure {
        case .notLive, .notPassed: return String(localizable: .increaseReputationIdentityNotPassed)
        case .alreadyClaimed: return String(localizable: .increaseReputationErrorAlreadyUsed)
        case .notConfigured, .unavailable: return String(localizable: .increaseReputationErrorUnavailable)
        default: return livenessFailureMessage(failure)
        }
    }

    static func livenessFailureMessage(_ failure: LivenessFailureModel) -> String {
        switch failure {
        case .notConfigured, .unavailable: return String(localizable: .increaseReputationLivenessErrorUnavailable)
        case .notLive, .notPassed: return String(localizable: .increaseReputationLivenessErrorNotLive)
        case .alreadyClaimed: return String(localizable: .increaseReputationLivenessErrorAlreadyClaimed)
        case .expired: return String(localizable: .increaseReputationLivenessErrorExpired)
        case .rejected, .alreadyVerified: return String(localizable: .increaseReputationLivenessErrorRejected)
        case .sponsorshipUnavailable: return String(localizable: .increaseReputationErrorGas)
        case .busy: return String(localizable: .increaseReputationErrorBusy)
        case .cancelled, .network, .unknown: return String(localizable: .increaseReputationErrorNetwork)
        }
    }
}
