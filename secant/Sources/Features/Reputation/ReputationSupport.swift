// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

extension Reputation {
    /// Micro-USDC as the exchange's own dollars, trailing zeros stripped — Android's
    /// `Usdc6.toDisplayString(stripTrailingZeros = true)`.
    static func usd(_ micros: String) -> String {
        guard let decimal = Decimal(string: micros) else { return micros }
        return NSDecimalNumber(decimal: decimal / 1_000_000).stringValue
    }

    /// One sentence per failure. None of them is "something went wrong": the three reverts that
    /// mean "one account, one wallet" already collapse into `alreadyVerifiedElsewhere` in the
    /// driver, and collapsing any further would leave the user with nothing to act on.
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
}
