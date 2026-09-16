// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
@preconcurrency import ZcashLightClientKit

extension KeystoneSigningClient: DependencyKey {
    static let liveValue: KeystoneSigningClient = {
        let broker = KeystoneSigningBroker()
        return KeystoneSigningClient(
            sign: { accountUUID, proposal in
                try await broker.sign(accountUUID: accountUUID, proposal: proposal)
            },
            events: { broker.events() },
            complete: { id, result in
                await broker.complete(id, result)
            }
        )
    }()
}

/// One parked continuation per request, resumed by `complete` or by the requester's own
/// cancellation. Subscribers are replayed the requests still pending when they attach, so a
/// request raised before `Root` started observing is not lost.
actor KeystoneSigningBroker {
    private struct Pending {
        let request: KeystoneSigningRequest
        let continuation: CheckedContinuation<KeystoneSignedPczt, Error>
    }

    private var pending: [UUID: Pending] = [:]
    /// `withTaskCancellationHandler` can run its handler before the continuation is parked, so a
    /// cancellation that finds nothing to withdraw is remembered and answered at parking time.
    private var cancelledBeforeParking: Set<UUID> = []
    private var subscribers: [UUID: AsyncStream<KeystoneSigningEvent>.Continuation] = [:]

    func sign(accountUUID: AccountUUID, proposal: Proposal) async throws -> KeystoneSignedPczt {
        let request = KeystoneSigningRequest(id: UUID(), accountUUID: accountUUID, proposal: proposal)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                park(request, continuation)
            }
        } onCancel: {
            Task { await self.withdraw(request.id) }
        }
    }

    func complete(_ id: UUID, _ result: Result<KeystoneSignedPczt, KeystoneSigningError>) {
        guard let parked = pending.removeValue(forKey: id) else { return }
        parked.continuation.resume(with: result)
    }

    nonisolated func events() -> AsyncStream<KeystoneSigningEvent> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.subscribe(id: id, continuation: continuation) }
            continuation.onTermination = { _ in
                Task { await self.unsubscribe(id: id) }
            }
        }
    }

    private func park(_ request: KeystoneSigningRequest, _ continuation: CheckedContinuation<KeystoneSignedPczt, Error>) {
        if cancelledBeforeParking.remove(request.id) != nil {
            continuation.resume(throwing: CancellationError())
            return
        }
        pending[request.id] = Pending(request: request, continuation: continuation)
        broadcast(.requested(request))
    }

    private func withdraw(_ id: UUID) {
        guard let parked = pending.removeValue(forKey: id) else {
            cancelledBeforeParking.insert(id)
            return
        }
        parked.continuation.resume(throwing: CancellationError())
        broadcast(.withdrawn(id))
    }

    private func broadcast(_ event: KeystoneSigningEvent) {
        for subscriber in subscribers.values {
            subscriber.yield(event)
        }
    }

    private func subscribe(id: UUID, continuation: AsyncStream<KeystoneSigningEvent>.Continuation) {
        subscribers[id] = continuation
        for parked in pending.values {
            continuation.yield(.requested(parked.request))
        }
    }

    private func unsubscribe(id: UUID) {
        subscribers[id] = nil
    }
}
