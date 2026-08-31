// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
@preconcurrency import ZappOfframp

extension DependencyValues {
    var onramp: OnrampClient {
        get { self[OnrampClient.self] }
        set { self[OnrampClient.self] = newValue }
    }
}

enum OnrampClientError: LocalizedError, Equatable {
    case authenticationCancelled
    case staleQuote
    case invalidFrameworkValue(String)

    var errorDescription: String? {
        switch self {
        case .authenticationCancelled: return String(localizable: .onrampErrorAuthenticationCancelled)
        case .staleQuote: return String(localizable: .onrampErrorStaleQuote)
        case .invalidFrameworkValue: return String(localizable: .onrampErrorProgress)
        }
    }
}

typealias OnrampStatusStream = AsyncThrowingStream<OnrampStatusModel, Error>
typealias OnrampDeliveryStream = AsyncThrowingStream<OnrampDeliveryModel, Error>

@DependencyClient
struct OnrampClient {
    var isConfigured: @Sendable () -> Bool = { false }
    var canDeliverToZec: @Sendable () async throws -> Bool
    var limits: @Sendable (_ currencyCode: String) async throws -> OnrampLimitsModel
    var recipientAddress: @Sendable () async throws -> String
    var quote: @Sendable (_ fiatMicros: String, _ currencyCode: String) async throws -> OnrampQuoteModel
    var estimateToZec: @Sendable (
        _ accountAddress: String,
        _ usdcMicros: String
    ) async throws -> OnrampZecEstimateModel
    var start: @Sendable (
        _ quote: OnrampQuoteModel,
        _ destination: OnrampDestinationModel,
        _ estimate: OnrampZecEstimateModel?
    ) async throws -> OnrampStatusStream
    var confirmPaid: @Sendable () async throws -> OnrampStatusStream
    var resume: @Sendable () async throws -> OnrampStatusStream
    var cancel: @Sendable () async throws -> OnrampStatusStream
    var deliverToZec: @Sendable (
        _ orderID: String,
        _ recipient: String,
        _ usdcMicros: String
    ) async throws -> OnrampDeliveryStream
    /// Picks the recorded delivery back up. A confirmed refund is replayed, never respent.
    var resumeDelivery: @Sendable () async throws -> OnrampDeliveryStream
    /// The user's explicit "convert again" — the only path allowed to spend a confirmed refund.
    var retryDelivery: @Sendable () async throws -> OnrampDeliveryStream
    var checkpoint: @Sendable () async throws -> OnrampCheckpointModel?
    var clearCheckpoint: @Sendable () async throws -> Void
    var declaredAmountDisagrees: @Sendable (
        _ currencyCode: String,
        _ status: OnrampStatusModel
    ) async throws -> Bool
    var transactionURL: @Sendable (_ txHash: String) async throws -> URL?
    var addressURL: @Sendable (_ address: String) async throws -> URL?
    var invalidateSession: @Sendable () async -> Void
}

extension OnrampClient: DependencyKey {
    static let liveValue = Self.live()

    static func live() -> Self {
        let authorization = OnrampQuoteAuthorization()
        return Self(
            isConfigured: {
                guard let value = PartnerKeys.p2pOnrampBaseUrl else { return false }
                return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            },
            canDeliverToZec: {
                try await OfframpSession.shared.onrampClient().canDeliverToZec
            },
            limits: { currencyCode in
                OnrampLimitsModel(try await OfframpSession.shared.onrampClient().limits(currencyCode: currencyCode))
            },
            recipientAddress: {
                try await OfframpSession.shared.onrampClient().recipientAddress()
            },
            quote: { fiatMicros, currencyCode in
                let generation = try await OfframpSession.shared.generationToken()
                let client = try await OfframpSession.shared.onrampClient()
                try await OfframpSession.shared.validateGeneration(generation)
                let native = try await client.quote(
                    fiatMicros: fiatMicros,
                    currencyCode: currencyCode
                )
                try await OfframpSession.shared.validateGeneration(generation)
                let model = OnrampQuoteModel(native)
                authorization.authorizeQuote(native, model: model, generation: generation)
                return model
            },
            estimateToZec: { accountAddress, usdcMicros in
                let generation = try await OfframpSession.shared.generationToken()
                let client = try await OfframpSession.shared.onrampClient()
                try await OfframpSession.shared.validateGeneration(generation)
                let native = try await client.estimateToZec(
                    accountAddress: accountAddress,
                    usdcMicros: usdcMicros
                )
                try await OfframpSession.shared.validateGeneration(generation)
                let model = OnrampZecEstimateModel(native)
                authorization.authorizeEstimate(native, model: model, generation: generation)
                return model
            },
            start: { quote, destination, estimate in
                @Dependency(\.localAuthentication) var authentication
                guard await authentication.authenticate() else { throw OnrampClientError.authenticationCancelled }
                guard let values = authorization.consume(quote: quote, estimate: estimate) else {
                    throw OnrampClientError.staleQuote
                }
                return try await OfframpSession.shared.startOnrampOrder(
                    quote: values.quote,
                    destination: destination.rawValue,
                    estimate: values.estimate,
                    expectedGeneration: values.generation
                )
            },
            confirmPaid: {
                let generation = try await OfframpSession.shared.generationToken()
                @Dependency(\.localAuthentication) var authentication
                guard await authentication.authenticate() else { throw OnrampClientError.authenticationCancelled }
                return try await OfframpSession.shared.confirmOnrampPaid(expectedGeneration: generation)
            },
            resume: {
                let generation = try await OfframpSession.shared.generationToken()
                return try await OfframpSession.shared.resumeOnrampOrder(expectedGeneration: generation)
            },
            cancel: {
                let generation = try await OfframpSession.shared.generationToken()
                return try await OfframpSession.shared.cancelOnrampOrder(expectedGeneration: generation)
            },
            deliverToZec: { orderID, recipient, usdcMicros in
                let generation = try await OfframpSession.shared.generationToken()
                @Dependency(\.localAuthentication) var authentication
                guard await authentication.authenticate() else { throw OnrampClientError.authenticationCancelled }
                return try await OfframpSession.shared.deliverOnrampToZec(
                    orderID: orderID,
                    recipient: recipient,
                    usdcMicros: usdcMicros,
                    expectedGeneration: generation
                )
            },
            resumeDelivery: {
                let generation = try await OfframpSession.shared.generationToken()
                return try await OfframpSession.shared.resumeOnrampDelivery(expectedGeneration: generation)
            },
            retryDelivery: {
                let generation = try await OfframpSession.shared.generationToken()
                @Dependency(\.localAuthentication) var authentication
                guard await authentication.authenticate() else { throw OnrampClientError.authenticationCancelled }
                return try await OfframpSession.shared.retryOnrampDelivery(expectedGeneration: generation)
            },
            checkpoint: {
                try await OfframpSession.shared.onrampClient().checkpoint().map(OnrampCheckpointModel.init)
            },
            clearCheckpoint: {
                try await OfframpSession.shared.clearOnrampCheckpoint()
            },
            declaredAmountDisagrees: { currencyCode, status in
                guard let instruction = status.instruction,
                      let expected = status.fiatMicros else { return false }
                return try await OfframpSession.shared.onrampClient().declaredAmountDisagrees(
                    currencyCode: currencyCode,
                    instructionKind: instruction.kind,
                    payload: instruction.payload,
                    expectedMicros: expected
                ).boolValue
            },
            transactionURL: { hash in
                URL(string: try await OfframpSession.shared.onrampClient().transactionUrl(txHash: hash))
            },
            addressURL: { address in
                URL(string: try await OfframpSession.shared.onrampClient().addressUrl(address: address))
            },
            invalidateSession: {
                authorization.reset()
                await OfframpSession.shared.invalidate()
            }
        )
    }
}

private final class OnrampQuoteAuthorization: @unchecked Sendable {
    private let lock = NSLock()
    private var quote: (model: OnrampQuoteModel, native: AppleOnrampQuote, generation: Int)?
    private var estimate: (model: OnrampZecEstimateModel, native: AppleOnrampZecEstimate, generation: Int)?

    func authorizeQuote(_ native: AppleOnrampQuote, model: OnrampQuoteModel, generation: Int) {
        lock.withLock {
            quote = (model, native, generation)
            estimate = nil
        }
    }

    func authorizeEstimate(_ native: AppleOnrampZecEstimate, model: OnrampZecEstimateModel, generation: Int) {
        lock.withLock { estimate = (model, native, generation) }
    }

    func consume(
        quote model: OnrampQuoteModel,
        estimate estimateModel: OnrampZecEstimateModel?
    ) -> (quote: AppleOnrampQuote, estimate: AppleOnrampZecEstimate?, generation: Int)? {
        lock.withLock {
            guard let quote, quote.model == model else { return nil }
            let nativeEstimate: AppleOnrampZecEstimate?
            if let estimateModel {
                guard let estimate,
                      estimate.model == estimateModel,
                      estimate.generation == quote.generation else { return nil }
                nativeEstimate = estimate.native
            } else {
                nativeEstimate = nil
            }
            self.quote = nil
            self.estimate = nil
            return (quote.native, nativeEstimate, quote.generation)
        }
    }

    func reset() {
        lock.withLock {
            quote = nil
            estimate = nil
        }
    }
}

private extension OnrampLimitsModel {
    init(_ value: AppleOnrampLimits) {
        self.init(
            enabled: value.enabled,
            currencyCode: value.currencyCode,
            minimumFiatMicros: value.minimumFiatMicros,
            maximumFiatMicros: value.maximumFiatMicros,
            dailyFiatMicros: value.dailyFiatMicros
        )
    }
}

private extension OnrampQuoteModel {
    init(_ value: AppleOnrampQuote) {
        self.init(
            quoteID: value.quoteId,
            currencyCode: value.currencyCode,
            fiatMicros: value.fiatMicros,
            grossUsdcMicros: value.grossUsdcMicros,
            feeUsdcMicros: value.feeUsdcMicros,
            netUsdcMicros: value.netUsdcMicros,
            buyPriceMicros: value.buyPriceMicros,
            expiresAt: Date(timeIntervalSince1970: TimeInterval(value.expiresAtMillis) / 1_000)
        )
    }
}

private extension OnrampZecEstimateModel {
    init(_ value: AppleOnrampZecEstimate) {
        self.init(
            depositAddress: value.depositAddress,
            zcashRecipient: value.zcashRecipient,
            deadline: Date(timeIntervalSince1970: TimeInterval(value.deadlineMillis) / 1_000),
            outputZec: value.outputZec,
            inputUsd: value.inputUsd,
            outputUsd: value.outputUsd,
            costBasisPoints: Int(value.costBasisPoints)
        )
    }
}

extension OnrampStatusModel {
    init(_ value: AppleOnrampStatus) throws {
        guard let kind = Kind(rawValue: value.kind) else {
            throw OnrampClientError.invalidFrameworkValue("status kind")
        }
        let instruction: OnrampPaymentInstructionModel?
        switch value.instructionKind {
        case "upi":
            guard let address = value.instructionAddress, let payload = value.instructionPayload else {
                throw OnrampClientError.invalidFrameworkValue("UPI instruction")
            }
            instruction = .upi(address: address, payload: payload)
        case "qr":
            guard let payload = value.instructionPayload else {
                throw OnrampClientError.invalidFrameworkValue("QR instruction")
            }
            instruction = .qr(payload: payload)
        case "fields":
            instruction = .fields(value.instructionFields.map { OnrampFieldModel(label: $0.label, value: $0.value) })
        case "plain":
            guard let address = value.instructionAddress else {
                throw OnrampClientError.invalidFrameworkValue("plain instruction")
            }
            instruction = .plain(address: address)
        case nil:
            instruction = nil
        default:
            throw OnrampClientError.invalidFrameworkValue("payment instruction")
        }
        self.init(
            kind: kind,
            phase: OnrampPhaseModel(value.phase),
            id: value.id,
            orderID: value.orderId,
            failureCode: value.failureCode.flatMap(OnrampFailureCodeModel.init(rawValue:)),
            instruction: instruction,
            fiatMicros: value.fiatMicros,
            netUsdcMicros: value.netUsdcMicros,
            recipientAddress: value.recipientAddress,
            paidTransactionHash: value.paidTx,
            expiresAt: value.expiresAtMillis.map { Date(timeIntervalSince1970: TimeInterval($0.int64Value) / 1_000) },
            isTerminal: value.isTerminal
        )
    }
}

extension OnrampDeliveryModel {
    init(_ value: AppleOnrampDeliveryStatus) throws {
        guard let kind = Kind(rawValue: value.kind) else {
            throw OnrampClientError.invalidFrameworkValue("delivery status kind")
        }
        self.init(
            kind: kind,
            stage: OnrampDeliveryPhaseModel(value.stage),
            inputUsdcMicros: value.inputUsdcMicros,
            outputZec: value.outputZec,
            refundedUsdcMicros: value.refundedUsdcMicros,
            baseAccount: value.baseAccount,
            baseTransactionHash: value.baseTransactionHash,
            fundsLocation: value.fundsLocation.map(OnrampFundsLocationModel.init),
            retryable: value.retryable,
            isTerminal: value.isTerminal,
            isSuccess: value.isSuccess
        )
    }
}

private extension OnrampCheckpointModel {
    init(_ value: AppleOnrampCheckpoint) {
        self.init(
            id: value.id,
            phase: OnrampPhaseModel(value.phase),
            orderID: value.orderId,
            destination: OnrampDestinationModel(rawValue: value.destination) ?? .base,
            zecDelivery: value.zecDelivery.map(OnrampDeliveryCheckpointModel.init)
        )
    }
}

private extension OnrampDeliveryCheckpointModel {
    init(_ value: AppleOnrampDeliveryCheckpoint) {
        self.init(
            phase: OnrampDeliveryPhaseModel(value.phase),
            usdcMicros: value.usdcMicros,
            baseAccount: value.baseAccount,
            transferStarted: value.transferStarted,
            refundedUsdcMicros: value.refundedUsdcMicros,
            acceptedCostBasisPoints: value.acceptedCostBps.map { Int($0.int32Value) },
            fundsLocation: OnrampFundsLocationModel(value.fundsLocation)
        )
    }
}

enum OnrampReservation: Sendable {
    case delivery(BaseUSDCReservationLedger.Owner)

    func record(_ status: OnrampDeliveryModel) async -> Bool {
        let owner: BaseUSDCReservationLedger.Owner
        switch self { case let .delivery(value): owner = value }
        // Funds location is stronger than the presentation kind. `awaitingZec` already follows an
        // exact Base receipt, and KMP intentionally stops reporting a pending Base commitment at
        // that point; settle it now so a screen close cannot strand an owner that resume cannot map.
        switch status.fundsLocation {
        case .nearIntent, .zcashWallet:
            await OfframpSession.shared.settleOnrampDelivery(owner, as: .spent)
            return true
        case .baseRefundConfirmed:
            await OfframpSession.shared.settleOnrampDelivery(owner, as: .available)
            return true
        case .baseAccount, .recipientMismatch, .transferAmbiguous, .unknown, nil:
            break
        }
        switch status.kind {
        case .delivered:
            await OfframpSession.shared.settleOnrampDelivery(owner, as: .spent)
            return true
        case .refundedToBase:
            await OfframpSession.shared.settleOnrampDelivery(owner, as: .available)
            return true
        case .failed:
            switch status.fundsLocation {
            case .baseAccount, .recipientMismatch, .baseRefundConfirmed:
                await OfframpSession.shared.settleOnrampDelivery(owner, as: .available)
            case .nearIntent, .zcashWallet:
                await OfframpSession.shared.settleOnrampDelivery(owner, as: .spent)
            case .transferAmbiguous, .unknown, nil:
                await OfframpSession.shared.settleOnrampDelivery(owner, as: .unknown)
            }
            return true
        case .preparing, .submitting, .awaitingZec:
            return false
        }
    }

    func finishInterrupted(receivedStatus: Bool) async {
        let owner: BaseUSDCReservationLedger.Owner
        switch self { case let .delivery(value): owner = value }
        do {
            let pending = try await OfframpSession.shared.pendingOnrampCommitmentForSettlement()
            await OfframpSession.shared.settleOnrampDelivery(
                owner,
                as: pending == nil && !receivedStatus ? .available : .unknown
            )
        } catch {
            await OfframpSession.shared.settleOnrampDelivery(owner, as: .unknown)
        }
    }
}
