//
//  PushTopicReconciler.swift
//  Zapp
//

import Foundation

protocol PushTopicSubscriptionClient: Sendable {
    func subscribe(to topic: String) async throws
    func unsubscribe(from topic: String) async throws
}

protocol PushTopicSubscriptionStore: Sendable {
    func load() async -> PushSubscriptionState
    func save(_ state: PushSubscriptionState) async
}

struct PushSubscriptionState: Codable, Equatable, Sendable {
    var deliveryEnabled = false
    var desiredBindings: [String: PushTopicBinding] = [:]
    var routableBindings: [String: PushTopicBinding] = [:]
    var subscribedTopics: Set<String> = []
}

enum PushTopicDesiredBindings {
    static func make(
        snapshot: PushTopicSnapshot,
        blockedWriters: Set<String>
    ) -> [String: PushTopicBinding] {
        guard snapshot.hydrated else { return [:] }

        let normalizedBlocked = Set(blockedWriters.map(normalizeKey))
        return snapshot.conversations
            .filter { $0.lifecycle == "ready" }
            .flatMap(\.inboundTopics)
            .filter { !normalizedBlocked.contains(normalizeKey($0.writerPublicKey)) }
            .reduce(into: [String: PushTopicBinding]()) { result, binding in
                result[binding.topic] = binding
            }
    }

    private static func normalizeKey(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: "0x", with: "", options: .anchored)
    }
}

/// Serial, idempotent reconciliation of opaque JS-derived topics. A failed
/// unsubscribe deliberately retains its routing binding so a late doorbell can
/// still be checked against the blocked writer and routed safely.
actor PushTopicReconciler {
    private let client: any PushTopicSubscriptionClient
    private let store: any PushTopicSubscriptionStore
    private let onFailure: @Sendable () -> Void

    init(
        client: any PushTopicSubscriptionClient,
        store: any PushTopicSubscriptionStore,
        onFailure: @escaping @Sendable () -> Void = { }
    ) {
        self.client = client
        self.store = store
        self.onFailure = onFailure
    }

    /// `desired == nil` is an unhydrated snapshot and must never erase restored
    /// subscriptions. Disabling is authoritative even when hydration is absent.
    func reconcile(desired: [String: PushTopicBinding]?, enabled: Bool) async {
        var state = await store.load()
        state.deliveryEnabled = enabled

        guard enabled else {
            state.desiredBindings = [:]
            await unsubscribeStale(desiredTopics: [], state: &state)
            await store.save(state)
            return
        }

        guard let desired else {
            await store.save(state)
            return
        }

        state.desiredBindings = desired

        // Refresh mappings for subscriptions that remain desired.
        for topic in state.subscribedTopics.intersection(desired.keys) {
            state.routableBindings[topic] = desired[topic]
        }
        await store.save(state)

        await unsubscribeStale(desiredTopics: Set(desired.keys), state: &state)

        for topic in Set(desired.keys).subtracting(state.subscribedTopics).sorted() {
            do {
                try await client.subscribe(to: topic)
                state.subscribedTopics.insert(topic)
                state.routableBindings[topic] = desired[topic]
                await store.save(state)
            } catch {
                onFailure()
            }
        }

        await store.save(state)
    }

    func forceResubscribe() async {
        var state = await store.load()
        guard state.deliveryEnabled else { return }

        for topic in state.desiredBindings.keys.sorted() {
            do {
                try await client.subscribe(to: topic)
                state.subscribedTopics.insert(topic)
                state.routableBindings[topic] = state.desiredBindings[topic]
                await store.save(state)
            } catch {
                onFailure()
            }
        }
        await store.save(state)
    }

    private func unsubscribeStale(
        desiredTopics: Set<String>,
        state: inout PushSubscriptionState
    ) async {
        for topic in state.subscribedTopics.subtracting(desiredTopics).sorted() {
            do {
                try await client.unsubscribe(from: topic)
                state.subscribedTopics.remove(topic)
                state.routableBindings.removeValue(forKey: topic)
                await store.save(state)
            } catch {
                onFailure()
            }
        }
    }
}

final class UserDefaultsPushTopicStore: PushTopicSubscriptionStore, @unchecked Sendable {
    private enum Constants {
        static let key = "zapp.push.subscriptionState.v1"
    }

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() async -> PushSubscriptionState { loadSynchronously() }

    func save(_ state: PushSubscriptionState) async {
        lock.withLock {
            guard let data = try? JSONEncoder().encode(state) else { return }
            defaults.set(data, forKey: Constants.key)
        }
    }

    func loadSynchronously() -> PushSubscriptionState {
        lock.withLock {
            guard let data = defaults.data(forKey: Constants.key),
                  let state = try? JSONDecoder().decode(PushSubscriptionState.self, from: data) else {
                return PushSubscriptionState()
            }
            return state
        }
    }

    func binding(for topic: String) -> PushTopicBinding? {
        loadSynchronously().routableBindings[topic]
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
