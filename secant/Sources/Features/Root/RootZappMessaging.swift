//
//  RootZappMessaging.swift
//  Zapp
//
//  Root owns the chat subsystem's lifetime, not the Chats tab.
//
//  The worklet must keep ingesting messages while the user is on Pay or You —
//  that is what accrues the unread badge on the nav pill — so the subscription
//  belongs here, beside `.observeTransactions` and `.observeShieldingProcessor`,
//  and not in a screen's `.onAppear`.
//

@preconcurrency import Combine
import ComposableArchitecture
import Foundation

extension Root {
    func zappMessagingReduce() -> Reduce<Root.State, Root.Action> {
        Reduce { state, action in
            switch action {
            case .observeZappMessaging:
                zappMessaging.start()

                return .merge(
                    .publisher {
                        zappMessaging.stateStream()
                            .throttle(for: .seconds(0.2), scheduler: mainQueue, latest: true)
                            .map(Root.Action.zappMessagingStateChanged)
                    }
                    .cancellable(id: state.zappMessagingCancelId, cancelInFlight: true),
                    .publisher {
                        chatPushNotifications.conversationTapStream()
                            .receive(on: mainQueue)
                            .map(Root.Action.chatNotificationTapped)
                    }
                    .cancellable(id: state.chatNotificationTapCancelId, cancelInFlight: true)
                )

            // Re-entering the room already on screen would stack a second copy of it, so the
            // first back press would appear to do nothing.
            case .chatNotificationTapped(let conversationId):
                guard state.path != .chatRoom || state.chatRoomState.conversationId != conversationId else {
                    return .none
                }

                state.chatRoomState = .initial
                state.chatRoomState.conversationId = conversationId
                state.chatRoomState.unreadMessageCountAtEntry =
                    state.zappMessagingState.unreadCount(for: conversationId)
                state.chatRoomState.conversation = state.chatsListState.conversations
                    .first { $0.id == conversationId }
                state.path = .chatRoom
                return .none

            case .zappMessagingStateChanged(let messagingState):
                state.zappMessagingState = messagingState
                state.zappTabsState.chatUnreadCount = messagingState.totalUnreadCount
                state.zappTabsState.hasChatIdentity = messagingState.identity != nil
                state.zappTabsState.displayName = messagingState.identity?.displayName
                return .none

            default: return .none
            }
        }
    }
}
