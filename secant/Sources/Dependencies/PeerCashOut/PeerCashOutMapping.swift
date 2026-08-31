// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
@preconcurrency import ZappOfframp

/// The one place Kotlin's Peer shapes become Swift's. Everything above this file works in
/// `Equatable`, `Sendable` value types and never imports `ZappOfframp`.
///
/// Unknown codes are the interesting case. They can only mean the framework moved ahead of the app,
/// and the safe reading differs per field: a phase falls back to the one that shows the least, a
/// step to the one that claims the least progress, and a buyer's outcome to `unknown` — which the
/// protocol already treats as "holds no funds and paid nothing", so it can never unlock a
/// withdrawal on its own.

extension PeerCapabilities {
    init(_ value: ApplePeerCapabilities) {
        self.init(
            isAvailable: value.isAvailable,
            destinations: value.platforms.map(PeerDestination.init),
            recommendedMinimum: UsdcAmount(micros: value.recommendedMinimumMicros) ?? .zero,
            attemptIDByteCount: Int(value.attemptIdByteCount)
        )
    }
}

extension PeerDestination {
    init(_ value: ApplePeerPlatformCapability) {
        self.init(
            code: value.code,
            currencies: value.currencies.map(PeerFiatCurrency.init),
            defaultCurrencyCodes: value.defaultCurrencyCodes,
            validatesHandleLive: value.validatesHandleLive,
            offersCurrencyChoice: value.offersCurrencyChoice
        )
    }
}

extension PeerFiatCurrency {
    init(_ value: ApplePeerCurrency) {
        self.init(code: value.code, symbol: value.symbol, precision: Int(value.precision))
    }
}

extension PeerHandleCheck {
    init(_ value: ApplePeerHandleCheck) {
        self.init(
            normalized: value.normalized,
            changedWhatWasTyped: value.changedWhatWasTyped,
            validatesLive: value.validatesLive
        )
    }
}

extension PeerAccount {
    init(_ value: ApplePeerAccount) {
        self.init(
            address: value.address,
            balance: value.balanceMicros.flatMap { UsdcAmount(micros: $0) },
            explorerURL: URL(string: value.explorerUrl)
        )
    }
}

extension PeerRate {
    /// A rate that will not parse is no rate. Showing an unparsed one would put a number beside a
    /// currency code without either of them meaning anything.
    init?(_ value: ApplePeerRate) {
        guard let fiatPerUsdc = Decimal(string: value.fiatPerUsdc, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        self.init(
            currencyCode: value.currencyCode,
            fiatPerUsdc: fiatPerUsdc,
            readAt: Date(timeIntervalSince1970: TimeInterval(value.readAtEpochSeconds))
        )
    }
}

extension PeerMarketReading {
    init(_ value: ApplePeerMarket) {
        self.init(
            currencyCode: value.currencyCode,
            verdict: Verdict(rawValue: value.verdict) ?? .unknown,
            averageFill: value.averageFillMicros.flatMap { UsdcAmount(micros: $0) },
            waitLowSeconds: Int(value.waitLowSeconds),
            waitHighSeconds: Int(value.waitHighSeconds),
            isOversized: value.isOversized
        )
    }
}

extension PeerAttempt {
    init(_ value: ApplePeerAttempt) {
        self.init(
            id: value.id,
            destinationCode: value.platformCode,
            currencyCodes: value.currencyCodes,
            amount: UsdcAmount(micros: value.amountMicros) ?? .zero,
            createdAt: Date(timeIntervalSince1970: TimeInterval(value.createdAtEpochSeconds)),
            depositID: value.depositIdComposite,
            holdsUnescrowedFunds: value.holdsUnescrowedFunds
        )
    }
}

extension PeerProgress {
    init(_ value: ApplePeerStatus) {
        self.init(
            subjectID: value.subjectId,
            kind: Kind(rawValue: value.kind) ?? .idle,
            step: Step(rawValue: value.step) ?? .initialization,
            amount: value.amountMicros.flatMap { UsdcAmount(micros: $0) },
            txHash: value.txHash,
            depositID: value.depositIdComposite,
            order: value.order.map(PeerOrder.init),
            failure: value.failure.map(PeerFailure.init),
            isTerminal: value.isTerminal
        )
    }
}

extension PeerFailure {
    init(_ value: ApplePeerFailure) {
        self.init(
            code: value.code,
            step: PeerProgress.Step(rawValue: value.step) ?? .initialization,
            retryable: value.retryable,
            allowsManualRetry: value.allowsManualRetry,
            nothingEscrowed: value.nothingEscrowed,
            recovery: Recovery(value),
            escrowRevertBucket: value.escrowRevertBucket
        )
    }
}

private extension PeerFailure.Recovery {
    init?(_ value: ApplePeerFailure) {
        switch value.recoveryKind {
        case ApplePeerFailure.Companion.shared.RECOVERY_INSPECT_TRANSACTION:
            guard let hash = value.recoveryTxHash else { return nil }
            self = .inspectTransaction(hash: hash)
        case ApplePeerFailure.Companion.shared.RECOVERY_INSPECT_DEPOSITOR:
            guard let address = value.recoveryAddress else { return nil }
            self = .inspectDepositor(address: address)
        default:
            return nil
        }
    }
}

extension PeerOrder {
    init(_ value: ApplePeerOrder) {
        self.init(
            depositID: value.depositIdComposite,
            // An unrecognised phase reads as waiting, which offers nothing and claims nothing.
            phase: Phase(rawValue: value.phase) ?? .waiting,
            isFinished: value.isFinished,
            acceptingIntents: value.acceptingIntents,
            gross: UsdcAmount(micros: value.grossMicros) ?? .zero,
            remaining: UsdcAmount(micros: value.remainingMicros) ?? .zero,
            sold: UsdcAmount(micros: value.soldMicros) ?? .zero,
            locked: UsdcAmount(micros: value.lockedMicros) ?? .zero,
            withdrawn: UsdcAmount(micros: value.withdrawnMicros) ?? .zero,
            withdrawable: UsdcAmount(micros: value.withdrawableMicros) ?? .zero,
            destinationCode: value.platformCode,
            currencyCodes: value.currencies.compactMap(\.code),
            buyerLegs: value.intents.map(PeerBuyerLeg.init),
            offersWithdrawal: value.offersWithdrawal,
            offersMatchingToggle: value.offersMatchingToggle,
            isHiddenFromBuyers: value.isHiddenFromBuyers,
            openedAt: value.openedAtEpochSeconds?.date,
            lastActivityAt: value.lastActivityAtEpochSeconds?.date,
            explorerURL: value.explorerUrl.flatMap { URL(string: $0) }
        )
    }
}

extension PeerBuyerLeg {
    init(_ value: ApplePeerIntent) {
        self.init(
            intentHash: value.intentHash,
            outcome: Outcome(rawValue: value.outcome) ?? .unknown,
            amount: UsdcAmount(micros: value.amountMicros) ?? .zero,
            paymentCurrencyCode: value.paymentCurrencyCode,
            paymentAmount: value.paymentAmount,
            signalledAt: value.signalledAtEpochSeconds?.date,
            expiresAt: value.expiresAtEpochSeconds?.date,
            holdsFunds: value.holdsFunds
        )
    }
}

private extension KotlinLong {
    var date: Date { Date(timeIntervalSince1970: TimeInterval(int64Value)) }
}
