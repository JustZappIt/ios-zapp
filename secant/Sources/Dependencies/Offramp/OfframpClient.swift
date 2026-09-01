// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
@preconcurrency import ZappOfframp

struct OfframpCorridor: Equatable, Identifiable, Sendable {
    let currencyCode: String
    let countryName: String
    let paymentRail: String
    let flag: String
    let symbol: String
    let precision: Int
    var id: String { currencyCode }
}

struct OfframpScanResult: Equatable, Sendable {
    let rawPayload: String
    let paymentAddress: String
    let fiatAmount: String?
}

struct OfframpQuoteModel: Equatable, Sendable {
    let currencyCode: String
    let fiatAmount: String
    let usdcMicros: String
    let usdcDisplay: String
    let sellRate: String
    let fixedFeeDisplay: String
    /// Order plus the protocol's fixed PAY fee: the exact Base allowance and reservation.
    let requiredBalanceMicros: String
    let baseBalanceDisplay: String
    let shortfallMicros: String
    let shortfallDisplay: String
    let canPayFromBase: Bool
    let canBridgeToBase: Bool
}

struct OfframpAccountModel: Equatable, Sendable {
    let address: String
    let balanceMicros: String?
    let balanceDisplay: String?
    let explorerURL: URL?
    let canBridgeToBase: Bool
    let canRefundToZec: Bool
}

struct OfframpProgressModel: Equatable, Sendable {
    let kind: String
    let step: String
    let title: String
    let detail: String?
    let orderId: String?
    let txHash: String?
    let bridgeDepositAddress: String?
    let isTerminal: Bool
    let isSuccess: Bool
}

struct OfframpHistoryModel: Equatable, Identifiable, Sendable {
    let id: String
    let status: String
    let orderType: String
    let currencyCode: String
    let usdcMicros: String
    let fiatMicros: String
    let placedAt: Date?
    let completedAt: Date?
    let cancelledAt: Date?
    let paymentAddress: String?
    let merchantAddress: String?
    let fixedFeeMicros: String?

    var type: OfframpHistoryOrderType? { OfframpHistoryOrderType(rawValue: orderType.uppercased()) }
}

enum OfframpHistoryOrderType: String, Equatable, Sendable {
    case buy = "BUY"
    case sell = "SELL"
    case pay = "PAY"

    var label: String {
        switch self {
        case .buy: return String(localizable: .offrampHistoryTypeBuy)
        case .sell: return String(localizable: .offrampHistoryTypeSell)
        case .pay: return String(localizable: .offrampHistoryTypePay)
        }
    }
}

enum OfframpClientError: LocalizedError, Equatable {
    case configuration(String)
    case invalidQR(String)
    case unsupportedAccount
    case authenticationCancelled
    case staleQuote

    var errorDescription: String? {
        switch self {
        case .configuration(let message): return message
        case .invalidQR(let code): return "That QR is not valid for this payment method (\(code))."
        case .unsupportedAccount: return "P2P payments currently require a Zapp software wallet."
        case .authenticationCancelled: return "Authentication was cancelled. No payment was submitted."
        case .staleQuote: return "The payment quote changed. Review the updated amount before trying again."
        }
    }
}

extension DependencyValues {
    var offramp: OfframpClient {
        get { self[OfframpClient.self] }
        set { self[OfframpClient.self] = newValue }
    }
}

@DependencyClient
struct OfframpClient {
    var corridors: @Sendable () async throws -> [OfframpCorridor]
    var parseQR: @Sendable (_ currencyCode: String, _ rawPayload: String) async throws -> OfframpScanResult
    var quote: @Sendable (_ currencyCode: String, _ fiatAmount: String) async throws -> OfframpQuoteModel
    var pay: @Sendable (
        _ quote: OfframpQuoteModel,
        _ payeeName: String?
    ) async throws -> AsyncStream<OfframpProgressModel>
    var resumePayment: @Sendable () async throws -> AsyncStream<OfframpProgressModel>
    var submitPaymentDetails: @Sendable (_ scan: OfframpScanResult) async throws -> Void
    var bridgeToBase: @Sendable (_ usdcMicros: String, _ resumeHandle: String?) async throws -> AsyncStream<OfframpProgressModel>
    var previewTopUp: @Sendable (_ usdcMicros: String) async throws -> OfframpBridgePreview
    var history: @Sendable () async throws -> [OfframpHistoryModel]
    var recoverFunds: @Sendable (_ orderId: String?) async throws -> AsyncStream<OfframpProgressModel>
    var previewRefund: @Sendable () async throws -> OfframpBridgePreview
    var hasCheckpoint: @Sendable () async throws -> Bool
    var checkpointCurrencyCode: @Sendable () async throws -> String?
    var discardCheckpoint: @Sendable () async throws -> Void
    var hasTopUpCheckpoint: @Sendable () async throws -> Bool
    var topUpCheckpointMicros: @Sendable () async throws -> String?
    var discardTopUpCheckpoint: @Sendable () async throws -> Void
    var accountAddress: @Sendable () async throws -> String
    var accountSummary: @Sendable () async throws -> OfframpAccountModel
    var transactionURL: @Sendable (_ txHash: String) async throws -> URL?
    /// Drops screen-owned authorization and payment-detail waiters without touching the
    /// wallet-lifetime account, Peer runner, or another P2P screen's work.
    var resetScreen: @Sendable () async -> Void
    var invalidateSession: @Sendable () async -> Void

    /// The owner key behind the P2P cash-out account, for the profile's reveal surface.
    /// See `OfframpWalletKey.swift` — the secret never leaves a `RedactableString`.
    var exportWalletKey: @Sendable () async throws -> OfframpWalletKey
}

extension OfframpClient: DependencyKey {
    static let liveValue = Self.live()

    static func live() -> Self {
        let paymentDetails = OfframpPaymentDetailsHost()
        let quoteAuthorization = OfframpQuoteAuthorization()
        return Self(
            corridors: {
                try await OfframpSession.shared.client().corridors().map(OfframpCorridor.init)
            },
            parseQR: { currency, payload in
                guard payload.utf8.count <= 16_384 else {
                    throw OfframpClientError.invalidQR("payload_too_large")
                }
                let parsed = try await OfframpSession.shared.client().parsePaymentQr(
                    currencyCode: currency,
                    rawPayload: payload
                )
                guard parsed.isValid, let address = parsed.paymentAddress else {
                    throw OfframpClientError.invalidQR(parsed.errorCode ?? "invalid_format")
                }
                return OfframpScanResult(rawPayload: payload, paymentAddress: address, fiatAmount: parsed.fiatAmount)
            },
            quote: { currency, amount in
                let result = try await OfframpSession.shared.quote(currencyCode: currency, fiatAmount: amount)
                guard let required = UsdcAmount(micros: result.native.requiredBalanceMicros),
                      let availableBalance = result.spendable.available else {
                    throw BaseUSDCReservationLedger.ClaimError.recoveryUnavailable
                }
                let model = OfframpQuoteModel(
                    result.native,
                    availableBalance: availableBalance,
                    required: required
                )
                quoteAuthorization.authorize(
                    result.native,
                    model: model,
                    generation: result.generation,
                    operationID: UUID().uuidString
                )
                return model
            },
            pay: { quote, payeeName in
                @Dependency(\.localAuthentication) var authentication
                guard await authentication.authenticate() else { throw OfframpClientError.authenticationCancelled }
                await paymentDetails.reset()
                guard let authorization = quoteAuthorization.consume(matching: quote) else {
                    throw OfframpClientError.staleQuote
                }
                guard let required = UsdcAmount(micros: quote.requiredBalanceMicros) else {
                    throw BaseUSDCReservationLedger.ClaimError.recoveryUnavailable
                }
                // The quote is advisory; this is the atomic commit-time admission shared with
                // Peer and refunds, using a fresh chain balance after authentication.
                return try await OfframpSession.shared.startScanAndPay(
                    quote: authorization.native,
                    paymentDetailsProvider: paymentDetails,
                    payeeName: payeeName,
                    amount: required,
                    quoteGeneration: authorization.generation,
                    operationID: authorization.operationID
                )
            },
            resumePayment: {
                let generation = try await OfframpSession.shared.generationToken()
                @Dependency(\.localAuthentication) var authentication
                guard await authentication.authenticate() else { throw OfframpClientError.authenticationCancelled }
                await paymentDetails.reset()
                return try await OfframpSession.shared.resumeScanAndPay(
                    paymentDetailsProvider: paymentDetails,
                    expectedGeneration: generation
                )
            },
            submitPaymentDetails: { scan in
                try await paymentDetails.submit(scan)
            },
            bridgeToBase: { micros, resume in
                let generation = try await OfframpSession.shared.generationToken()
                @Dependency(\.localAuthentication) var authentication
                guard await authentication.authenticate() else { throw OfframpClientError.authenticationCancelled }
                return try await OfframpSession.shared.bridgeToBase(
                    usdcMicros: micros,
                    resumeDepositAddress: resume,
                    expectedGeneration: generation
                )
            },
            previewTopUp: { micros in
                try await OfframpSession.shared.previewTopUp(usdcMicros: micros)
            },
            history: {
                try await OfframpSession.shared.client().history().map(OfframpHistoryModel.init)
            },
            recoverFunds: { orderId in
                let generation = try await OfframpSession.shared.generationToken()
                @Dependency(\.localAuthentication) var authentication
                guard await authentication.authenticate() else { throw OfframpClientError.authenticationCancelled }
                // Preview is deliberately not a reservation. Confirmation rechecks and takes the
                // exclusive claim immediately before the recover/refund flow can move anything.
                return try await OfframpSession.shared.recoverFunds(
                    orderID: orderId,
                    expectedGeneration: generation
                )
            },
            previewRefund: {
                try await OfframpSession.shared.previewRefund()
            },
            hasCheckpoint: {
                try await OfframpSession.shared.client().hasCheckpoint().boolValue
            },
            checkpointCurrencyCode: {
                try await OfframpSession.shared.client().checkpointCurrencyCode()
            },
            discardCheckpoint: {
                try await OfframpSession.shared.discardPaymentCheckpoint()
            },
            hasTopUpCheckpoint: {
                try await OfframpSession.shared.client().hasTopUpCheckpoint().boolValue
            },
            topUpCheckpointMicros: {
                try await OfframpSession.shared.client().topUpCheckpointMicros()
            },
            discardTopUpCheckpoint: {
                try await OfframpSession.shared.discardTopUpCheckpoint()
            },
            accountAddress: {
                try await OfframpSession.shared.client().accountAddress()
            },
            accountSummary: {
                OfframpAccountModel(try await OfframpSession.shared.client().accountSummary())
            },
            transactionURL: { hash in
                URL(string: try await OfframpSession.shared.client().transactionUrl(txHash: hash))
            },
            resetScreen: {
                await paymentDetails.reset()
                quoteAuthorization.reset()
            },
            invalidateSession: {
                await paymentDetails.reset()
                quoteAuthorization.reset()
                await OfframpSession.shared.invalidate()
            },
            exportWalletKey: {
                try OfframpWalletKey.derive()
            }
        )
    }
}

private final class OfframpQuoteAuthorization: @unchecked Sendable {
    private let lock = NSLock()
    private var authorized: (model: OfframpQuoteModel, native: AppleOfframpQuote, generation: Int, operationID: String)?

    func authorize(_ native: AppleOfframpQuote, model: OfframpQuoteModel, generation: Int, operationID: String) {
        lock.withLock { authorized = (model, native, generation, operationID) }
    }

    func consume(matching model: OfframpQuoteModel) -> (native: AppleOfframpQuote, generation: Int, operationID: String)? {
        lock.withLock {
            guard let authorized, authorized.model == model else { return nil }
            self.authorized = nil
            return (authorized.native, authorized.generation, authorized.operationID)
        }
    }

    func reset() {
        lock.withLock { authorized = nil }
    }
}

private enum OfframpPaymentDetailsError: LocalizedError {
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cancelled: return "The merchant payment-details request was cancelled."
        }
    }
}

/// One suspended request per payment. The shared engine calls this only after merchant acceptance;
/// the scanner resumes it with a locally validated QR payload.
private final class OfframpPaymentDetailsHost: NSObject, AppleOfframpPaymentDetailsProvider, @unchecked Sendable {
    private let worker = OfframpPaymentDetailsWorker()

    func __requestPaymentDetails(
        orderId: String,
        currencyCode: String,
        fiatAmount: String,
        completionHandler: @escaping @Sendable (AppleOfframpPaymentDetails?, Error?) -> Void
    ) {
        Task {
            do { completionHandler(try await worker.waitForDetails(), nil) }
            catch { completionHandler(nil, error) }
        }
    }

    func submit(_ scan: OfframpScanResult) async throws {
        await worker.submit(scan)
    }

    func reset() async {
        await worker.reset()
    }
}

private actor OfframpPaymentDetailsWorker {
    private var continuation: CheckedContinuation<AppleOfframpPaymentDetails, Error>?
    private var pending: AppleOfframpPaymentDetails?

    func waitForDetails() async throws -> AppleOfframpPaymentDetails {
        if let pending {
            self.pending = nil
            return pending
        }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func submit(_ scan: OfframpScanResult) {
        let details = AppleOfframpPaymentDetails(
            rawPayload: scan.rawPayload,
            paymentAddress: scan.paymentAddress,
            fiatAmount: scan.fiatAmount
        )
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: details)
        } else {
            pending = details
        }
    }

    func reset() {
        continuation?.resume(throwing: OfframpPaymentDetailsError.cancelled)
        continuation = nil
        pending = nil
    }
}

private extension OfframpCorridor {
    init(_ value: ApplePaymentCorridor) {
        self.init(
            currencyCode: value.currencyCode,
            countryName: value.countryName,
            paymentRail: value.paymentRail,
            flag: value.flag,
            symbol: value.symbol,
            precision: Int(value.precision)
        )
    }
}

private extension OfframpQuoteModel {
    init(_ value: AppleOfframpQuote, availableBalance: UsdcAmount, required: UsdcAmount) {
        let shortfall = required.subtractingClampedToZero(availableBalance)
        self.init(
            currencyCode: value.currencyCode,
            fiatAmount: value.fiatAmount,
            usdcMicros: value.usdcMicros,
            usdcDisplay: value.usdcDisplay,
            sellRate: value.sellRate,
            fixedFeeDisplay: value.fixedFeeDisplay,
            requiredBalanceMicros: value.requiredBalanceMicros,
            baseBalanceDisplay: availableBalance.display,
            shortfallMicros: shortfall.microsString,
            shortfallDisplay: shortfall.display,
            canPayFromBase: availableBalance >= required,
            canBridgeToBase: value.canBridgeToBase
        )
    }
}

private extension OfframpAccountModel {
    init(_ value: AppleOfframpAccountSummary) {
        self.init(
            address: value.address,
            balanceMicros: value.balanceMicros,
            balanceDisplay: value.balanceDisplay,
            explorerURL: URL(string: value.explorerUrl),
            canBridgeToBase: value.canBridgeToBase,
            canRefundToZec: value.canRefundToZec
        )
    }
}

extension OfframpProgressModel {
    init(_ value: AppleOfframpStatus) {
        self.init(
            kind: value.kind,
            step: value.step,
            title: value.title,
            detail: value.detail,
            orderId: value.orderId,
            txHash: value.txHash,
            bridgeDepositAddress: value.bridgeDepositAddress,
            isTerminal: value.isTerminal,
            isSuccess: value.isSuccess
        )
    }
}

private extension OfframpHistoryModel {
    init(_ value: AppleOfframpHistoryItem) {
        self.init(
            id: value.orderId,
            status: value.status,
            orderType: value.orderType,
            currencyCode: value.currencyCode,
            usdcMicros: value.usdcMicros,
            fiatMicros: value.fiatMicros,
            placedAt: value.placedAtEpochSeconds?.date,
            completedAt: value.completedAtEpochSeconds?.date,
            cancelledAt: value.cancelledAtEpochSeconds?.date,
            paymentAddress: value.paymentAddress,
            merchantAddress: value.merchantAddress,
            fixedFeeMicros: value.fixedFeeMicros
        )
    }
}

private extension KotlinLong {
    var date: Date { Date(timeIntervalSince1970: TimeInterval(int64Value)) }
}

enum OfframpReservation: Sendable {
    case scanAndPay(BaseUSDCReservationLedger.Owner)
    case refund(BaseUSDCReservationLedger.Owner)

    func record(_ status: OfframpProgressModel) async -> Bool {
        switch self {
        case let .scanAndPay(owner):
            switch status.kind {
            case "waiting_for_payment_details", "sending_payment_details", "waiting_for_completion", "completed":
                await OfframpSession.shared.settleScanAndPay(owner, as: .spent)
                return true
            case "cancelled":
                // Contract cancellation is positive evidence that the order's USDC returned.
                await OfframpSession.shared.settleScanAndPay(owner, as: .available)
                return true
            case "failed":
                await settleScanFailure(status, owner: owner)
                return true
            default:
                return false
            }
        case let .refund(owner):
            switch status.kind {
            case "funds_recovered":
                await OfframpSession.shared.settleRefund(owner, as: .spent)
                return true
            case "failed":
                await settleRefundFailure(owner: owner)
                return true
            default:
                return false
            }
        }
    }

    /// Cancellation before a cold flow emits is the only no-status path that may release a claim,
    /// and only when the durable checkpoint also proves nothing started. Once any status was seen,
    /// a missing checkpoint could be terminal cleanup, so the disposition remains unknown.
    func finishInterrupted(receivedStatus: Bool) async {
        switch self {
        case let .scanAndPay(owner):
            do {
                let pending = try await OfframpSession.shared.pendingScanAndPayCommitmentForSettlement()
                await OfframpSession.shared.settleScanAndPay(
                    owner,
                    as: pending == nil && !receivedStatus ? .available : .unknown
                )
            } catch {
                await OfframpSession.shared.settleScanAndPay(owner, as: .unknown)
            }
        case let .refund(owner):
            do {
                let pending = try await OfframpSession.shared.pendingRefundCommitmentForSettlement()
                await OfframpSession.shared.settleRefund(
                    owner,
                    as: pending == nil && !receivedStatus ? .available : .unknown
                )
            } catch {
                await OfframpSession.shared.settleRefund(owner, as: .unknown)
            }
        }
    }

    private func settleScanFailure(
        _ status: OfframpProgressModel,
        owner: BaseUSDCReservationLedger.Owner
    ) async {
        let escrowedSteps = [
            "WAITING_FOR_PAYMENT_DETAILS",
            "ENCRYPTING_UPI",
            "SENDING_UPI",
            "WAITING_FOR_COMPLETION"
        ]
        if escrowedSteps.contains(status.step) {
            await OfframpSession.shared.settleScanAndPay(owner, as: .spent)
            return
        }
        do {
            let pending = try await OfframpSession.shared.pendingScanAndPayCommitmentForSettlement()
            await OfframpSession.shared.settleScanAndPay(owner, as: pending == nil ? .available : .unknown)
        } catch {
            await OfframpSession.shared.settleScanAndPay(owner, as: .unknown)
        }
    }

    private func settleRefundFailure(owner: BaseUSDCReservationLedger.Owner) async {
        do {
            let pending = try await OfframpSession.shared.pendingRefundCommitmentForSettlement()
            await OfframpSession.shared.settleRefund(owner, as: pending == nil ? .available : .unknown)
        } catch {
            await OfframpSession.shared.settleRefund(owner, as: .unknown)
        }
    }
}
