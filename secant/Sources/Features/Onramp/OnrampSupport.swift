// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

extension Onramp {
    static func fiatMicros(_ value: String) -> String? {
        guard var decimal = Decimal(string: value), decimal > 0 else { return nil }
        decimal *= 1_000_000
        var rounded = Decimal()
        NSDecimalRound(&rounded, &decimal, 0, .down)
        return NSDecimalNumber(decimal: rounded).stringValue
    }

    static func displayMicros(_ value: String) -> String {
        guard let decimal = Decimal(string: value) else { return value }
        return NSDecimalNumber(decimal: decimal / 1_000_000).stringValue
    }

    static func withinLimits(_ amount: String, limits: OnrampLimitsModel) -> Bool {
        guard let value = Decimal(string: amount),
              let minimum = Decimal(string: limits.minimumFiatMicros),
              let maximum = Decimal(string: limits.maximumFiatMicros) else { return false }
        return limits.enabled && value >= minimum && value <= maximum
    }

    static func baseRefundState(_ account: OfframpAccountModel?) -> BaseRefundState {
        guard let account, let micros = account.balanceMicros, Decimal(string: micros).map({ $0 > 0 }) == true else {
            return .hidden
        }
        return account.canRefundToZec ? .available : .blocked
    }

    static func failureMessage(_ code: OnrampFailureCodeModel?) -> String {
        switch code {
        case .badRequest: return String(localizable: .onrampErrorLimits)
        case .unauthenticated, .nonceInvalid: return String(localizable: .onrampErrorUnauthenticated)
        case .recipientNotAllowed: return String(localizable: .onrampErrorRecipientNotAllowed)
        case .routeDisabled: return String(localizable: .onrampErrorCorridorDisabled)
        case .orderNotFound: return String(localizable: .onrampErrorOrderNotFound)
        case .wrongPhase: return String(localizable: .onrampErrorWrongPhase)
        case .quoteExpired: return String(localizable: .onrampErrorQuoteExpired)
        case .capExceeded: return String(localizable: .onrampErrorCapExceeded)
        case .screeningRejected: return String(localizable: .onrampErrorScreeningRejected)
        case .upstreamFailed, .operatorUnavailable, .networkUnavailable:
            return String(localizable: .onrampErrorBackendUnavailable)
        case .noMerchant: return String(localizable: .onrampErrorNoMerchant)
        case .orderExpired: return String(localizable: .onrampErrorOrderExpired)
        case .unknown, nil: return String(localizable: .onrampErrorProgress)
        }
    }

    static func deliveryFailureMessage(_ location: OnrampFundsLocationModel?) -> String {
        switch location {
        case .baseAccount: return String(localizable: .onrampConversionFailedOnBase)
        case .recipientMismatch: return String(localizable: .onrampConversionRecipientMismatch)
        default: return String(localizable: .onrampConversionStatusUncertain)
        }
    }
}
