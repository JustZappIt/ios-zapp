//
//  RootPushNotifications.swift
//  Zapp
//

@preconcurrency import Combine
import ComposableArchitecture
import Foundation

extension Root {
    func pushNotificationsReduce() -> Reduce<Root.State, Root.Action> {
        Reduce { state, action in
            switch action {
            case .observePushNotifications:
                return .merge(
                    .publisher {
                        pushNotifications.eventStream()
                            .receive(on: mainQueue)
                            .map(Root.Action.pushNotificationEvent)
                    }
                    .cancellable(id: state.pushNotificationEventsCancelId, cancelInFlight: true),
                    .publisher {
                        zappMessaging.pushTopicsChangedStream()
                            .receive(on: mainQueue)
                            .map { Root.Action.reconcilePushNotifications }
                    }
                    .cancellable(id: state.pushTopicsCancelId, cancelInFlight: true),
                    .send(.reconcilePushNotifications)
                )

            case .pushNotificationEvent(let event):
                switch event {
                case .readinessChanged, .authorizationChanged, .tokenRefreshed:
                    return .send(.reconcilePushNotifications)

                case .tapped(.chats):
                    state.zappTabsState.selectedTab = .chats
                    state.path = nil
                    return .none

                case .tapped(.conversation(let conversationId)):
                    state.zappTabsState.selectedTab = .chats
                    state.chatRoomState = .initial
                    state.chatRoomState.conversationId = conversationId
                    state.chatRoomState.conversation = state.chatsListState.conversations
                        .first { $0.id == conversationId }
                    state.path = .chatRoom
                    return .none
                }

            case .reconcilePushNotifications:
                guard state.zappMessagingState.isReady else { return .none }
                let blockedWriters = state.chatContacts.blockedKeys

                return .run { _ in
                    do {
                        let snapshot = try await zappMessaging.getPushTopicSnapshot()
                        let converted = PushTopicSnapshot(
                            version: snapshot.version,
                            hydrated: snapshot.hydrated,
                            supportsGroups: snapshot.supportsGroups,
                            conversations: snapshot.conversations.map { conversation in
                                PushTopicConversation(
                                    conversationId: conversation.conversationId,
                                    lifecycle: conversation.lifecycle,
                                    inboundTopics: conversation.inboundTopics.map { topic in
                                        PushTopicBinding(
                                            topic: topic.topic,
                                            conversationId: conversation.conversationId,
                                            writerPublicKey: topic.writerPublicKey
                                        )
                                    }
                                )
                            }
                        )
                        await pushNotifications.reconcile(converted, blockedWriters)
                    } catch {
                        // A booting or recovering worklet is equivalent to an
                        // unhydrated snapshot. Never erase restored subscriptions.
                        await pushNotifications.reconcile(nil, blockedWriters)
                    }
                }

            default:
                return .none
            }
        }
    }
}
