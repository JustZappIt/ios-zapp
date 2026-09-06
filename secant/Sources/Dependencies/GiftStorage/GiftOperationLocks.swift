// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation

extension DependencyValues {
    /// Serializes funding work per card id, so an explicit submit and a startup reconciliation can
    /// never both create a transaction for one card.
    var giftFundingOperationLock: GiftOperationLockClient {
        get { self[GiftFundingOperationLockKey.self] }
        set { self[GiftFundingOperationLockKey.self] = newValue }
    }

    /// Serializes claim work per card address. The SDK has no in-process alias guard, so this lock
    /// is the only thing preventing two live synchronizers on one card's database.
    var giftClaimOperationLock: GiftOperationLockClient {
        get { self[GiftClaimOperationLockKey.self] }
        set { self[GiftClaimOperationLockKey.self] = newValue }
    }
}

@DependencyClient
struct GiftOperationLockClient {
    var acquire: @Sendable (_ key: String) async throws -> Void
    var release: @Sendable (_ key: String) async -> Void
}

extension GiftOperationLockClient {
    /// Run `body` holding the key's mutex. The FIFO handoff in `KeyedAsyncLock` is what makes
    /// "concurrent submit and reconciliation create one active transaction" hold.
    func withLock<T>(_ key: String, _ body: () async throws -> T) async throws -> T {
        try await acquire(key)
        if Task.isCancelled {
            await release(key)
            throw CancellationError()
        }
        do {
            let result = try await body()
            await release(key)
            return result
        } catch {
            await release(key)
            throw error
        }
    }

    static func live() -> Self {
        let lock = KeyedAsyncLock()
        return Self(
            acquire: { try await lock.acquire($0) },
            release: { await lock.release($0) }
        )
    }
}

private enum GiftFundingOperationLockKey: DependencyKey {
    static let liveValue: GiftOperationLockClient = .live()
    /// Tests get a pass-through lock; concurrency tests override with `.live()` explicitly.
    static let testValue = GiftOperationLockClient(acquire: { _ in }, release: { _ in })
}

private enum GiftClaimOperationLockKey: DependencyKey {
    static let liveValue: GiftOperationLockClient = .live()
    static let testValue = GiftOperationLockClient(acquire: { _ in }, release: { _ in })
}

extension KeyedAsyncLock {
    /// Run `body` holding the key's mutex, releasing on every path.
    nonisolated func withLock<T: Sendable>(_ key: String, _ body: @Sendable () async throws -> T) async throws -> T {
        try await acquire(key)
        do {
            let result = try await body()
            await release(key)
            return result
        } catch {
            await release(key)
            throw error
        }
    }
}

/// A fair (FIFO) async mutex per string key — the `TransactionGuard` discipline, keyed.
actor KeyedAsyncLock {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private var busy: Set<String> = []
    private var waiters: [String: [Waiter]] = [:]

    /// Wait until the key is free, then take it. Cancellation-aware: a task cancelled while
    /// parked resumes by throwing without taking the lock.
    func acquire(_ key: String) async throws {
        guard busy.contains(key) else {
            busy.insert(key)
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                waiters[key, default: []].append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id, key: key) }
        }
    }

    /// Release the key, handing ownership to its next waiter (FIFO) if there is one.
    func release(_ key: String) {
        guard var queue = waiters[key], !queue.isEmpty else {
            busy.remove(key)
            return
        }
        let next = queue.removeFirst()
        waiters[key] = queue.isEmpty ? nil : queue
        next.continuation.resume() // The key stays busy — ownership transfers to the resumed waiter.
    }

    private func cancelWaiter(_ id: UUID, key: String) {
        guard var queue = waiters[key], let index = queue.firstIndex(where: { $0.id == id }) else { return }
        let waiter = queue.remove(at: index)
        waiters[key] = queue.isEmpty ? nil : queue
        waiter.continuation.resume(throwing: CancellationError())
    }
}
