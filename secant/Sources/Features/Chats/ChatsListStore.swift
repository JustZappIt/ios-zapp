//
//  ChatsListStore.swift
//  Zapp
//

import ComposableArchitecture
import Foundation
import ZappMessaging

@Reducer
struct ChatsList {
    @ObservableState
    struct State: Equatable {
        var conversations: [ZMConversation] = []
        var messagingState = ZappMessagingState()

        /// Distinguishes "no conversations yet" from "the first snapshot has not arrived".
        var isLoaded = false

        var conversationsCancelId = UUID()
        var stateCancelId = UUID()

        var sortedConversations: [ZMConversation] {
            conversations.sorted {
                ($0.lastMessageTimestamp ?? .distantPast) > ($1.lastMessageTimestamp ?? .distantPast)
            }
        }

        init() { }
    }

    enum Action: Equatable {
        case onAppear
        case onDisappear
        case conversationsUpdated([ZMConversation])
        case messagingStateChanged(ZappMessagingState)

        // Root routes these; the tab stays navigation-agnostic.
        case conversationTapped(String)
        case newConversationTapped
    }

    @Dependency(\.mainQueue) var mainQueue
    @Dependency(\.zappMessaging) var zappMessaging

    init() { }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.messagingState = zappMessaging.latestState()

                return .merge(
                    .publisher {
                        zappMessaging.conversationsStream()
                            .map(ChatsList.Action.conversationsUpdated)
                    }
                    .cancellable(id: state.conversationsCancelId, cancelInFlight: true),
                    .publisher {
                        zappMessaging.stateStream()
                            .throttle(for: .seconds(0.2), scheduler: mainQueue, latest: true)
                            .map(ChatsList.Action.messagingStateChanged)
                    }
                    .cancellable(id: state.stateCancelId, cancelInFlight: true),
                    .run { _ in try? await zappMessaging.refreshConversations() }
                )

            case .onDisappear:
                return .merge(
                    .cancel(id: state.conversationsCancelId),
                    .cancel(id: state.stateCancelId)
                )

            case .conversationsUpdated(let conversations):
                state.conversations = conversations
                state.isLoaded = true
                return .none

            case .messagingStateChanged(let messagingState):
                state.messagingState = messagingState
                return .none

            case .conversationTapped, .newConversationTapped:
                return .none
            }
        }
    }
}

// MARK: Placeholders

extension ChatsList.State {
    static var initial: ChatsList.State {
        .init()
    }
}

extension ChatsList {
    @MainActor
    static let initial = StoreOf<ChatsList>(
        initialState: .initial
    ) {
        ChatsList()
    }
}
