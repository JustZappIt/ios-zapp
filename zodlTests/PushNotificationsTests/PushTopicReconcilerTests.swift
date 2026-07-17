//
//  PushTopicReconcilerTests.swift
//  zodlTests
//

import Foundation
import Testing
@testable import zodl_internal

@Suite struct PushTopicReconcilerTests {
    @Test func subscribesNewAndRemovesStaleTopics() async {
        let fixture = Fixture(state: state(topics: ["old"]))
        await fixture.reconciler.reconcile(desired: bindings(["new"]), enabled: true)

        #expect(await fixture.client.subscribed == ["new"])
        #expect(await fixture.client.unsubscribed == ["old"])
        #expect(await fixture.store.load().subscribedTopics == ["new"])
    }

    @Test func unhydratedSnapshotRetainsExistingSubscriptions() async {
        let fixture = Fixture(state: state(topics: ["existing"]))
        await fixture.reconciler.reconcile(desired: nil as [String: PushTopicBinding]?, enabled: true)

        #expect(await fixture.client.subscribed.isEmpty)
        #expect(await fixture.client.unsubscribed.isEmpty)
        #expect(await fixture.store.load().subscribedTopics == ["existing"])
    }

    @Test func tokenRefreshReassertsDesiredSubscriptions() async {
        let fixture = Fixture(state: state(topics: ["desired"]))
        await fixture.reconciler.forceResubscribe()

        #expect(await fixture.client.subscribed == ["desired"])
        #expect(await fixture.client.unsubscribed.isEmpty)
    }

    @Test func disabledNotificationsUnsubscribeEverything() async {
        let fixture = Fixture(state: state(topics: ["one", "two"]))
        await fixture.reconciler.reconcile(desired: nil as [String: PushTopicBinding]?, enabled: false)

        #expect(await fixture.client.unsubscribed == ["one", "two"])
        #expect(await fixture.store.load().subscribedTopics.isEmpty)
        #expect(await fixture.store.load().desiredBindings.isEmpty)
    }

    @Test func conversationRemovalUnsubscribesItsTopic() async {
        let fixture = Fixture(state: state(topics: ["kept", "removed"]))
        await fixture.reconciler.reconcile(desired: bindings(["kept"]), enabled: true)

        #expect(await fixture.client.unsubscribed == ["removed"])
        #expect(await fixture.store.load().subscribedTopics == ["kept"])
    }

    @Test func blockedWritersAreExcludedFromDesiredTopics() {
        let allowed = binding(topic: "allowed", writer: "aabb")
        let blocked = binding(topic: "blocked", writer: "0xCCDD")
        let snapshot = PushTopicSnapshot(
            version: 1,
            hydrated: true,
            supportsGroups: false,
            conversations: [
                PushTopicConversation(
                    conversationId: "direct",
                    lifecycle: "ready",
                    inboundTopics: [allowed, blocked]
                ),
                PushTopicConversation(
                    conversationId: "pending",
                    lifecycle: "pending",
                    inboundTopics: [binding(topic: "pending", writer: "eeff")]
                )
            ]
        )

        let desired = PushTopicDesiredBindings.make(snapshot: snapshot, blockedWriters: ["ccdd"])
        #expect(Set(desired.keys) == ["allowed"])
    }
}

private extension PushTopicReconcilerTests {
    final class Fixture: @unchecked Sendable {
        let client = RecordingSubscriptionClient()
        let store: MemoryPushTopicStore
        let reconciler: PushTopicReconciler

        init(state: PushSubscriptionState) {
            store = MemoryPushTopicStore(state: state)
            reconciler = PushTopicReconciler(client: client, store: store)
        }
    }

    func binding(topic: String, writer: String = "writer") -> PushTopicBinding {
        PushTopicBinding(topic: topic, conversationId: "conversation-\(topic)", writerPublicKey: writer)
    }

    func bindings(_ topics: [String]) -> [String: PushTopicBinding] {
        Dictionary(uniqueKeysWithValues: topics.map { ($0, binding(topic: $0)) })
    }

    func state(topics: Set<String>) -> PushSubscriptionState {
        let desired = bindings(Array(topics))
        return PushSubscriptionState(
            deliveryEnabled: true,
            desiredBindings: desired,
            routableBindings: desired,
            subscribedTopics: topics
        )
    }
}

private actor RecordingSubscriptionClient: PushTopicSubscriptionClient {
    private(set) var subscribed: [String] = []
    private(set) var unsubscribed: [String] = []

    func subscribe(to topic: String) async throws { subscribed.append(topic) }
    func unsubscribe(from topic: String) async throws { unsubscribed.append(topic) }
}

private actor MemoryPushTopicStore: PushTopicSubscriptionStore {
    private var state: PushSubscriptionState

    init(state: PushSubscriptionState) { self.state = state }
    func load() async -> PushSubscriptionState { state }
    func save(_ state: PushSubscriptionState) async { self.state = state }
}
