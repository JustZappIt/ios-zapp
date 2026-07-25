//
//  SupportTicketListStore.swift
//  Zapp
//
//  Port of `screen/chat/support/SupportTicketListVM.kt` + `SupportTicketListState.kt`.
//
//  A "ticket" is one whole conversation, not a thread inside one: every topic the user picks
//  creates a separate group with the support agent, and this screen is the inbox of those groups.
//  Its rows therefore read exactly like chat-list rows — subject (the topic), last message,
//  relative time, unread chip — filtered to the support conversations the chat list hides.
//

import ComposableArchitecture
import Foundation
import ZappMessaging

@Reducer
struct SupportTicketList {
    /// One support conversation, as the list renders it.
    struct Ticket: Equatable, Identifiable {
        let conversationId: String
        let categoryLabel: String
        let lastMessage: String?
        let timeLabel: String?
        let unreadCount: Int

        var id: String { conversationId }
    }

    @ObservableState
    struct State: Equatable {
        @Presents var alert: AlertState<Action.Alert>?

        var conversations: [ZMConversation] = []
        var messagingState = ZappMessagingState()

        /// Distinguishes "no tickets" from "the first snapshot has not arrived".
        var isLoaded = false

        /// Topic per conversation, recovered from the `[Category: …]` marker the ticket opens
        /// with. Android caches the same lookup; an id that resolved to nothing stays in
        /// `resolvedCategoryIds` so a marker-less ticket is not re-fetched on every snapshot.
        var categories: [String: SupportCategory] = [:]
        var resolvedCategoryIds: Set<String> = []

        var conversationsCancelId = UUID()
        var stateCancelId = UUID()

        var localPublicKey: String? {
            messagingState.identity?.publicKey
        }

        var supportConversations: [ZMConversation] {
            conversations
                .filter { SupportChatConstants.isSupportConversation($0, localPublicKey: localPublicKey) }
                .sorted {
                    ($0.lastMessageTimestamp ?? .distantPast) > ($1.lastMessageTimestamp ?? .distantPast)
                }
        }

        var tickets: [Ticket] {
            supportConversations.map { conversation in
                Ticket(
                    conversationId: conversation.id,
                    categoryLabel: categories[conversation.id]?.displayName
                        ?? String(localizable: .supportTicketDefaultLabel),
                    lastMessage: conversation.lastMessage.map(SupportPreview.subtitle(for:)),
                    timeLabel: conversation.lastMessageTimestamp.map { ChatRelativeTime.label(for: $0) },
                    unreadCount: messagingState.unreadCount(for: conversation.id)
                )
            }
        }

        /// Tickets whose topic has not been looked up yet.
        var unresolvedCategoryIds: [String] {
            supportConversations
                .map(\.id)
                .filter { !resolvedCategoryIds.contains($0) }
        }

        init() { }
    }

    enum Action: Equatable {
        enum Alert: Equatable {
            case closeConfirmed(String)
        }

        case alert(PresentationAction<Alert>)
        case onAppear
        case onDisappear
        case conversationsUpdated([ZMConversation])
        case conversationsRefreshFailed
        case messagingStateChanged(ZappMessagingState)
        case categoriesLoaded([String: SupportCategory], attempted: Set<String>)
        case closeTicketRequested(String)
        case closeTicketFailed

        // Root routes these; the screen stays navigation-agnostic.
        case backTapped
        case newTicketTapped
        case ticketTapped(String)
    }

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
                            .map(SupportTicketList.Action.conversationsUpdated)
                    }
                    .cancellable(id: state.conversationsCancelId, cancelInFlight: true),
                    .publisher {
                        zappMessaging.stateStream()
                            .map(SupportTicketList.Action.messagingStateChanged)
                    }
                    .cancellable(id: state.stateCancelId, cancelInFlight: true),
                    .run { _ in
                        try await zappMessaging.refreshConversations()
                    } catch: { error, send in
                        LoggerProxy.error("Support ticket list refresh failed: \(error)")
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
                return loadCategories(for: state.unresolvedCategoryIds)

            case .conversationsRefreshFailed:
                state.isLoaded = true
                return .none

            case .messagingStateChanged(let messagingState):
                state.messagingState = messagingState
                // The identity arriving is what decides which side of `isSupportConversation`
                // this device is on, so the ticket set can only be complete once it lands.
                return loadCategories(for: state.unresolvedCategoryIds)

            case let .categoriesLoaded(categories, attempted):
                state.categories.merge(categories) { _, new in new }
                state.resolvedCategoryIds.formUnion(attempted)
                return .none

            case .closeTicketRequested(let conversationId):
                state.alert = AlertState.closeTicket(id: conversationId)
                return .none

                // Same close as the support chat's overflow menu: a bot-prefixed notice so the
                // agent sees the ticket end, then the conversation goes.
            case .alert(.presented(.closeConfirmed(let conversationId))):
                state.categories.removeValue(forKey: conversationId)
                state.resolvedCategoryIds.remove(conversationId)

                return .run { send in
                    do {
                        _ = try await zappMessaging.sendMessage(
                            conversationId,
                            "\(SupportChatConstants.botPrefix)\(String(localizable: .supportChatLeaveNotice))",
                            nil
                        )
                    } catch {
                        LoggerProxy.error("Support ticket list failed to post leave notice: \(error)")
                    }

                    do {
                        try await zappMessaging.removeConversation(conversationId)
                    } catch {
                        LoggerProxy.error("Support ticket list failed to close ticket: \(error)")
                        await send(.closeTicketFailed)
                    }
                }

            case .alert:
                return .none

            case .closeTicketFailed:
                return .none

            case .backTapped, .newTicketTapped, .ticketTapped:
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }

    /// Recovers each ticket's topic from its `[Category: …]` marker — the first message the ticket
    /// was opened with. Android reads the marker rather than the display name because the display
    /// name is group metadata that a rename could overwrite.
    private func loadCategories(for conversationIds: [String]) -> Effect<Action> {
        guard !conversationIds.isEmpty else { return .none }

        return .run { send in
            var resolved: [String: SupportCategory] = [:]

            for conversationId in conversationIds {
                do {
                    let messages = try await zappMessaging.messages(conversationId, supportCategoryLookupLimit)

                    if let category = messages.lazy
                        .compactMap({ SupportChatConstants.parseCategoryMarker($0.content) })
                        .first {
                        resolved[conversationId] = category
                    }
                } catch {
                    LoggerProxy.error("Support ticket list failed to read category for \(conversationId): \(error)")
                }
            }

            await send(.categoriesLoaded(resolved, attempted: Set(conversationIds)))
        }
    }
}

/// The ticket subtitle and the pinned chat-list row share one rule: strip the bot prefix, then run
/// the result through the same preview mapping every other conversation row uses, so a media or
/// structured message never shows its sentinel (or raw JSON) to the user.
enum SupportPreview {
    static func subtitle(for lastMessage: String) -> String {
        let stripped = SupportChatConstants.stripBotPrefix(lastMessage)

        return ChatPreviewSentinel.label(for: stripped)
            ?? ChatPreviewSentinel.jsonLabel(for: stripped)
            ?? stripped
    }
}

/// The marker is the ticket's first message; a small page is enough to find it.
private let supportCategoryLookupLimit = 20

// MARK: Alerts

extension AlertState where Action == SupportTicketList.Action.Alert {
    /// Mirrors Android's `support_ticket_close_dialog_*`.
    static func closeTicket(id: String) -> AlertState {
        AlertState {
            TextState(String(localizable: .supportTicketCloseDialogTitle))
        } actions: {
            ButtonState(role: .destructive, action: .closeConfirmed(id)) {
                TextState(String(localizable: .supportTicketCloseDialogConfirm))
            }

            ButtonState(role: .cancel) {
                TextState(String(localizable: .generalCancel))
            }
        } message: {
            TextState(String(localizable: .supportTicketCloseDialogMessage))
        }
    }
}

// MARK: Placeholders

extension SupportTicketList.State {
    static var initial: SupportTicketList.State {
        .init()
    }
}

extension SupportTicketList {
    @MainActor
    static let initial = StoreOf<SupportTicketList>(
        initialState: .initial
    ) {
        SupportTicketList()
    }
}
