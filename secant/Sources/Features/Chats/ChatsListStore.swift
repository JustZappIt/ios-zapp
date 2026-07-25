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
        /// Android persists the same flag as `IS_CHAT_TOS_ACCEPTED`.
        @Shared(.appStorage(.chatTermsAccepted)) var chatTermsAccepted = false

        @Presents var alert: AlertState<Action.Alert>?

        var conversations: [ZMConversation] = []
        var messagingState = ZappMessagingState()

        /// Distinguishes "no conversations yet" from "the first snapshot has not arrived".
        var isLoaded = false
        var showsNetworkDetails = false
        var isLoadingNetworkDetails = false
        var showsTermsDialog = false
        var connectionDetails: ZMConnectionDetails?

        var conversationsCancelId = UUID()
        var stateCancelId = UUID()

        /// Blocked DMs are hidden outright. A group is not hidden because one member
        /// is blocked — their messages are filtered inside the room instead.
        ///
        /// Phase 7 extension point: Android also splits the support conversations out of this list
        /// (`SupportChatConstants.isSupportConversation`) and pins one aggregate "Zapp Support" row
        /// above the timestamp-sorted remainder. Until the support subsystem lands, every
        /// conversation stays in the ordinary list.
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
        enum Alert: Equatable {
            case leaveConfirmed(String)
        }

        case alert(PresentationAction<Alert>)
        case onAppear
        case onDisappear
        case conversationsUpdated([ZMConversation])
        case conversationsRefreshFailed
        case messagingStateChanged(ZappMessagingState)
        case networkChipTapped
        case networkDetailsDismissed
        case networkDetailsLoaded(ZMConnectionDetails)
        case networkDetailsFailed
        case leaveConversationRequested(String)
        case termsAccepted
        case termsDeclined

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
                // Android's `checkTosAccepted`: the gate re-presents on every entry to
                // the tab until the terms are accepted.
                state.showsTermsDialog = !state.chatTermsAccepted

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

                // Android's `onLeaveRequest`: swipe and context menu both confirm before leaving.
            case .leaveConversationRequested(let conversationId):
                guard let conversation = state.conversations.first(where: { $0.id == conversationId }) else {
                    return .none
                }

                state.alert = AlertState.leaveConversation(
                    id: conversationId,
                    name: state.displayName(for: conversation)
                )
                return .none

            case .alert(.presented(.leaveConfirmed(let conversationId))):
                return .send(.removeConversationTapped(conversationId))

            case .alert:
                return .none

                // Both conversation types leave through `removeConversation`, matching Android's
                // `ChatConversationsRepository.leaveConversation`, which is the same SDK call.
            case .removeConversationTapped(let conversationId):
                return .run { _ in
                    try await zappMessaging.removeConversation(conversationId)
                } catch: { error, send in
                    LoggerProxy.error("Chat list failed to remove conversation: \(error)")
                    await send(.removeConversationFailed)
                }

            case .removeConversationFailed:
                return .none

            case .termsAccepted:
                state.$chatTermsAccepted.withLock { $0 = true }
                state.showsTermsDialog = false
                return .none

                // Declining leaves the tab: Root routes this back to the previously selected tab,
                // so the gate keeps its meaning instead of silently dropping the user into chat.
            case .termsDeclined:
                state.showsTermsDialog = false
                return .none

            case .conversationTapped, .newConversationTapped:
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
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

// MARK: Alerts

extension AlertState where Action == ChatsList.Action.Alert {
    /// Mirrors `ChatListLeaveDialog.kt`.
    static func leaveConversation(id: String, name: String) -> AlertState {
        AlertState {
            TextState(String(localizable: .chatListLeaveDialogTitle))
        } actions: {
            ButtonState(role: .destructive, action: .leaveConfirmed(id)) {
                TextState(String(localizable: .chatListLeaveDialogConfirm))
            }

            ButtonState(role: .cancel) {
                TextState(String(localizable: .generalCancel))
            }
        } message: {
            TextState(String(localizable: .chatListLeaveDialogMessage(name)))
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
