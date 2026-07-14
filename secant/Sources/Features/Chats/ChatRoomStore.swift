//
//  ChatRoomStore.swift
//  Zapp
//

@preconcurrency import Combine
import ComposableArchitecture
import Foundation
import ZappMessaging

@Reducer
struct ChatRoom {
    @ObservableState
    struct State: Equatable {
        @Shared(.inMemory(.chatContacts)) var chatContacts: ChatContacts = .empty

        var conversationId: String
        var conversation: ZMConversation?
        var messages: [ZMMessage] = []
        var draft = ""
        var isLoading = true
        var sendDidFail = false
        var messagingState = ZappMessagingState()

        var messageReceivedCancelId = UUID()
        var messagingStateCancelId = UUID()

        var trimmedDraft: String {
            draft.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var title: String {
            guard let conversation else { return String(localizable: .chatRoomTitleFallback) }

            let name = conversation.resolvedDisplayName(chatContacts)

            return name.isEmpty ? String(localizable: .chatRoomTitleFallback) : name
        }

        /// Blocked senders are filtered on the way out too, not just at ingest: a
        /// cold load reads straight from the store, which knows nothing about blocks.
        var visibleMessages: [ZMMessage] {
            messages.filter { !chatContacts.isBlocked($0.senderId) }
        }

        func senderName(for message: ZMMessage) -> String? {
            message.resolvedSenderName(chatContacts)
        }

        /// OUR connectivity, not the peer's — `isOnline` is this node's swarm
        /// state, the same field the list's connection chip reads. There is no
        /// per-peer presence on the client yet (the SDK emits
        /// `connection.peer_status`, but nothing surfaces it), so claiming
        /// "Online" under someone's name would be a fabrication: it would read as
        /// present whenever *we* have a network, even if they have been dark for
        /// weeks. Say nothing while healthy, and only own up when we are offline.
        var subtitle: String? {
            messagingState.isOnline ? nil : String(localizable: .chatRoomPeerOffline)
        }

        init(conversationId: String, conversation: ZMConversation? = nil) {
            self.conversationId = conversationId
            self.conversation = conversation
        }
    }

    enum Action: Equatable {
        case onAppear
        case onDisappear
        case backToHomeTapped
        case draftChanged(String)
        case sendTapped
        case messagesLoaded([ZMMessage])
        case messageReceived(ZMMessage)
        case messagingStateChanged(ZappMessagingState)
        case sendFailed(String)
    }

    @Dependency(\.zappMessaging) var zappMessaging

    init() { }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                let conversationId = state.conversationId
                zappMessaging.setActiveConversation(conversationId)

                return .merge(
                    .run { _ in
                        try? await zappMessaging.markRead(conversationId)
                    },
                    .run { send in
                        let messages = try await zappMessaging.messages(conversationId, messagePageSize)
                        await send(.messagesLoaded(messages))
                    } catch: { error, send in
                        LoggerProxy.error("Chat room failed to load messages: \(error)")
                        await send(.messagesLoaded([]))
                    },
                    .publisher {
                        zappMessaging.messageReceivedStream()
                            .filter { $0.conversationId == conversationId }
                            .map(Action.messageReceived)
                    }
                    .cancellable(id: state.messageReceivedCancelId, cancelInFlight: true),
                    .publisher {
                        zappMessaging.stateStream()
                            .map(Action.messagingStateChanged)
                    }
                    .cancellable(id: state.messagingStateCancelId, cancelInFlight: true)
                )

            case .onDisappear:
                zappMessaging.setActiveConversation(nil)

                return .merge(
                    .cancel(id: state.messageReceivedCancelId),
                    .cancel(id: state.messagingStateCancelId)
                )

            case .backToHomeTapped:
                return .none

            case .draftChanged(let draft):
                state.draft = draft
                state.sendDidFail = false
                return .none

            case .sendTapped:
                let content = state.trimmedDraft
                guard !content.isEmpty else { return .none }

                state.draft = ""
                state.sendDidFail = false
                let conversationId = state.conversationId

                return .run { send in
                    let message = try await zappMessaging.sendMessage(conversationId, content)
                    await send(.messageReceived(message))
                } catch: { error, send in
                    LoggerProxy.error("Chat room failed to send message: \(error)")
                    await send(.sendFailed(content))
                }

            case .messagesLoaded(let messages):
                state.isLoading = false
                state.messages = messages.sorted { $0.timestamp < $1.timestamp }
                return .none

            case .messageReceived(let message):
                guard !state.chatContacts.isBlocked(message.senderId) else { return .none }
                guard !state.messages.contains(where: { $0.id == message.id }) else { return .none }

                state.messages.append(message)
                state.messages.sort { $0.timestamp < $1.timestamp }
                return .none

            case .messagingStateChanged(let messagingState):
                state.messagingState = messagingState
                return .none

            // Give the text back. The draft is cleared optimistically on send, so
            // without this a failed send destroys what the user typed, with no
            // bubble and no error — the message simply evaporates.
            case .sendFailed(let content):
                if state.draft.isEmpty {
                    state.draft = content
                }
                state.sendDidFail = true
                return .none
            }
        }
    }
}

private let messagePageSize = 50

// MARK: Placeholders

extension ChatRoom.State {
    static var initial: ChatRoom.State {
        .init(conversationId: "")
    }
}

extension ChatRoom {
    @MainActor
    static let initial = StoreOf<ChatRoom>(
        initialState: .initial
    ) {
        ChatRoom()
    }
}
