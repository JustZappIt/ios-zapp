// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation

extension Onramp {
    /// How a ZEC delivery leg is entered. Only `retry` may respend a confirmed refund, so the
    /// relaunch path has to name itself rather than borrow the user's explicit action.
    enum DeliveryEntry: Equatable {
        case fresh(orderID: String, recipient: String, usdcMicros: String)
        case resume
        case retry
    }

    func statusEffect(
        _ operation: @escaping @Sendable () async throws -> OnrampStatusStream
    ) -> Effect<Action> {
        .run { send in
            do {
                for try await status in try await operation() { await send(.statusReceived(status)) }
                await send(.statusStreamFinished)
            } catch OnrampClientError.authenticationCancelled {
                await send(.authenticationCancelled)
            } catch {
                await send(.statusOperationFailed(error.localizedDescription))
            }
        }
        .cancellable(id: CancelID.driver, cancelInFlight: true)
    }

    func deliveryEffect(_ entry: DeliveryEntry) -> Effect<Action> {
        .run { send in
            do {
                let stream: OnrampDeliveryStream
                switch entry {
                case let .fresh(orderID, recipient, usdcMicros):
                    stream = try await onramp.deliverToZec(orderID, recipient, usdcMicros)
                case .resume:
                    stream = try await onramp.resumeDelivery()
                case .retry:
                    stream = try await onramp.retryDelivery()
                }
                for try await status in stream { await send(.deliveryStatusReceived(status)) }
                await send(.deliveryStreamFinished)
            } catch {
                // Never infer the disposition of funds from an exception. The durable Kotlin
                // checkpoint records whether a transfer started and is the recovery authority.
                let checkpoint = try? await onramp.checkpoint()
                let delivery = checkpoint?.zecDelivery
                await send(.deliveryFailed(OnrampDeliveryModel(
                    kind: .failed,
                    stage: delivery?.phase ?? .needsAttention,
                    inputUsdcMicros: delivery?.usdcMicros,
                    outputZec: nil,
                    refundedUsdcMicros: delivery?.refundedUsdcMicros,
                    baseAccount: delivery?.baseAccount,
                    baseTransactionHash: nil,
                    fundsLocation: delivery?.fundsLocation ?? .transferAmbiguous,
                    retryable: delivery.map { !$0.transferStarted } ?? false,
                    isTerminal: false,
                    isSuccess: false
                )))
            }
        }
        .cancellable(id: CancelID.delivery, cancelInFlight: entry == .retry)
    }

    func quoteCountdown(to deadline: Date) -> Effect<Action> {
        countdown(to: deadline, tick: Action.quoteTicked, expired: .quoteExpired)
    }

    func paymentCountdown(_ status: OnrampStatusModel) -> Effect<Action> {
        guard let deadline = status.expiresAt, let orderID = status.orderID ?? status.id else { return .none }
        return countdown(to: deadline, tick: Action.paymentTicked, expired: .paymentWindowExpired(orderID))
    }

    func countdown(
        to deadline: Date,
        tick: @escaping @Sendable (Int) -> Action,
        expired: Action
    ) -> Effect<Action> {
        .run { [date, continuousClock] send in
            var remaining = max(0, Int(deadline.timeIntervalSince(date.now()).rounded(.down)))
            while !Task.isCancelled {
                await send(tick(remaining))
                if remaining <= 0 { break }
                try await continuousClock.sleep(for: .seconds(1))
                remaining -= 1
            }
            if !Task.isCancelled { await send(expired) }
        }
        .cancellable(id: CancelID.countdown, cancelInFlight: true)
    }

    func transactionURLEffect(_ hash: String?) -> Effect<Action> {
        guard let hash else { return .none }
        return .run { send in
            await send(.transactionURLLoaded(try? await onramp.transactionURL(hash)))
        }
    }

    func cancelEffects() -> Effect<Action> {
        .merge(
            .cancel(id: CancelID.load),
            .cancel(id: CancelID.quote),
            .cancel(id: CancelID.driver),
            .cancel(id: CancelID.countdown),
            .cancel(id: CancelID.confirmPaid),
            .cancel(id: CancelID.delivery),
            .cancel(id: CancelID.baseRefund)
        )
    }
}
