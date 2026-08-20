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
    ) async throws -> AsyncStream<OnrampStatusModel>
    var confirmPaid: @Sendable () async throws -> AsyncStream<OnrampStatusModel>
    var resume: @Sendable () async throws -> AsyncStream<OnrampStatusModel>
    var cancel: @Sendable () async throws -> AsyncStream<OnrampStatusModel>
    var deliverToZec: @Sendable (
        _ orderID: String,
        _ recipient: String,
        _ usdcMicros: String
    ) async throws -> AsyncStream<OnrampDeliveryModel>
    var retryDelivery: @Sendable () async throws -> AsyncStream<OnrampDeliveryModel>
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
                let native = try await OfframpSession.shared.onrampClient().quote(
                    fiatMicros: fiatMicros,
                    currencyCode: currencyCode
                )
                let model = OnrampQuoteModel(native)
                authorization.authorizeQuote(native, model: model)
                return model
            },
            estimateToZec: { accountAddress, usdcMicros in
                let native = try await OfframpSession.shared.onrampClient().estimateToZec(
                    accountAddress: accountAddress,
                    usdcMicros: usdcMicros
                )
                let model = OnrampZecEstimateModel(native)
                authorization.authorizeEstimate(native, model: model)
                return model
            },
            start: { quote, destination, estimate in
                @Dependency(\.localAuthentication) var authentication
                guard await authentication.authenticate() else { throw OnrampClientError.authenticationCancelled }
                guard let values = authorization.consume(quote: quote, estimate: estimate) else {
                    throw OnrampClientError.staleQuote
                }
                let flow = try await OfframpSession.shared.onrampClient().start(
                    quote: values.quote,
                    destination: destination.rawValue,
                    zecEstimate: values.estimate
                )
                return flow.onrampStream()
            },
            confirmPaid: {
                @Dependency(\.localAuthentication) var authentication
                guard await authentication.authenticate() else { throw OnrampClientError.authenticationCancelled }
                return try await OfframpSession.shared.onrampClient().confirmPaid().onrampStream()
            },
            resume: {
                try await OfframpSession.shared.onrampClient().resume().onrampStream()
            },
            cancel: {
                try await OfframpSession.shared.onrampClient().cancel().onrampStream()
            },
            deliverToZec: { orderID, recipient, usdcMicros in
                @Dependency(\.localAuthentication) var authentication
                guard await authentication.authenticate() else { throw OnrampClientError.authenticationCancelled }
                let flow = try await OfframpSession.shared.onrampClient().deliverToZec(
                    orderId: orderID,
                    recipient: recipient,
                    usdcMicros: usdcMicros
                )
                return flow.onrampDeliveryStream()
            },
            retryDelivery: {
                @Dependency(\.localAuthentication) var authentication
                guard await authentication.authenticate() else { throw OnrampClientError.authenticationCancelled }
                return try await OfframpSession.shared.onrampClient().retryDelivery().onrampDeliveryStream()
            },
            checkpoint: {
                try await OfframpSession.shared.onrampClient().checkpoint().map(OnrampCheckpointModel.init)
            },
            clearCheckpoint: {
                try await OfframpSession.shared.onrampClient().clearCheckpoint()
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
    private var quote: (model: OnrampQuoteModel, native: AppleOnrampQuote)?
    private var estimate: (model: OnrampZecEstimateModel, native: AppleOnrampZecEstimate)?

    func authorizeQuote(_ native: AppleOnrampQuote, model: OnrampQuoteModel) {
        lock.withLock {
            quote = (model, native)
            estimate = nil
        }
    }

    func authorizeEstimate(_ native: AppleOnrampZecEstimate, model: OnrampZecEstimateModel) {
        lock.withLock { estimate = (model, native) }
    }

    func consume(
        quote model: OnrampQuoteModel,
        estimate estimateModel: OnrampZecEstimateModel?
    ) -> (quote: AppleOnrampQuote, estimate: AppleOnrampZecEstimate?)? {
        lock.withLock {
            guard let quote, quote.model == model else { return nil }
            let nativeEstimate: AppleOnrampZecEstimate?
            if let estimateModel {
                guard let estimate, estimate.model == estimateModel else { return nil }
                nativeEstimate = estimate.native
            } else {
                nativeEstimate = nil
            }
            self.quote = nil
            self.estimate = nil
            return (quote.native, nativeEstimate)
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

private extension OnrampStatusModel {
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

private extension OnrampDeliveryModel {
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

private extension SkieSwiftFlow where T == AppleOnrampStatus {
    func onrampStream() -> AsyncStream<OnrampStatusModel> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    for await status in self {
                        guard !Task.isCancelled else { break }
                        continuation.yield(try OnrampStatusModel(status))
                    }
                } catch {
                    // Kotlin has already flattened all expected failures into status values.
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private extension SkieSwiftFlow where T == AppleOnrampDeliveryStatus {
    func onrampDeliveryStream() -> AsyncStream<OnrampDeliveryModel> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    for await status in self {
                        guard !Task.isCancelled else { break }
                        continuation.yield(try OnrampDeliveryModel(status))
                    }
                } catch {
                    // Kotlin has already flattened all expected failures into status values.
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
