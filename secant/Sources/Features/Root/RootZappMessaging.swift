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

                return .publisher {
                    zappMessaging.stateStream()
                        .throttle(for: .seconds(0.2), scheduler: mainQueue, latest: true)
                        .map(Root.Action.zappMessagingStateChanged)
                }
                .cancellable(id: state.zappMessagingCancelId, cancelInFlight: true)

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
