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
        @Shared(.inMemory(.chatContacts)) var chatContacts: ChatContacts = .empty

        var conversations: [ZMConversation] = []
        var messagingState = ZappMessagingState()

        /// Distinguishes "no conversations yet" from "the first snapshot has not arrived".
        var isLoaded = false
        var showsNetworkDetails = false
        var isLoadingNetworkDetails = false
        var connectionDetails: ZMConnectionDetails?

        var conversationsCancelId = UUID()
        var stateCancelId = UUID()

        /// Blocked DMs are hidden outright. A group is not hidden because one member
        /// is blocked — their messages are filtered inside the room instead.
        var sortedConversations: [ZMConversation] {
            conversations
                .filter { conversation in
                    guard conversation.type == .direct else { return true }

                    return !conversation.participantIds.contains { chatContacts.isBlocked($0) }
                }
                .sorted {
                    ($0.lastMessageTimestamp ?? .distantPast) > ($1.lastMessageTimestamp ?? .distantPast)
                }
        }

        func displayName(for conversation: ZMConversation) -> String {
            conversation.resolvedDisplayName(chatContacts)
        }

        init() { }
    }

    enum Action: Equatable {
        case onAppear
        case onDisappear
        case conversationsUpdated([ZMConversation])
        case conversationsRefreshFailed
        case messagingStateChanged(ZappMessagingState)
        case networkChipTapped
        case networkDetailsDismissed
        case networkDetailsLoaded(ZMConnectionDetails)
        case networkDetailsFailed

        // Root routes these; the tab stays navigation-agnostic.
        case conversationTapped(String)
        case removeConversationTapped(String)
        case removeConversationFailed
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
                    .run { _ in
                        try await zappMessaging.refreshConversations()
                    } catch: { error, send in
                        LoggerProxy.error("Chat list refresh failed: \(error)")
                        await send(.conversationsRefreshFailed)
                    }
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

            case .conversationsRefreshFailed:
                // Leave the last known list intact. The structured SDK failure is
                // visible from the network sheet instead of becoming an empty state.
                state.isLoaded = true
                return .none

            case .messagingStateChanged(let messagingState):
                state.messagingState = messagingState
                return .none

            case .networkChipTapped:
                state.showsNetworkDetails = true
                state.isLoadingNetworkDetails = true
                return loadNetworkDetails()

            case .networkDetailsDismissed:
                state.showsNetworkDetails = false
                return .none

            case .networkDetailsLoaded(let details):
                state.connectionDetails = details
                state.isLoadingNetworkDetails = false
                return .none

            case .networkDetailsFailed:
                state.connectionDetails = nil
                state.isLoadingNetworkDetails = false
                return .none

            case .removeConversationTapped(let conversationId):
                return .run { _ in
                    try await zappMessaging.removeConversation(conversationId)
                } catch: { error, send in
                    LoggerProxy.error("Chat list failed to remove conversation: \(error)")
                    await send(.removeConversationFailed)
                }

            case .removeConversationFailed:
                return .none

            case .conversationTapped, .newConversationTapped:
                return .none
            }
        }
    }

    private func loadNetworkDetails() -> Effect<Action> {
        .run { send in
            let details = try await zappMessaging.connectionDetails()
            await send(.networkDetailsLoaded(details))
        } catch: { error, send in
            LoggerProxy.error("Chat list failed to load network details: \(error)")
            await send(.networkDetailsFailed)
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
