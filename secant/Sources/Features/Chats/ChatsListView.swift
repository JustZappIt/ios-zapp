//
//  ChatsListView.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI
import ZappMessaging

/// The Chats tab root, mirroring `ChatListView.kt`.
///
/// Android also pins a "Zapp Support" row and swipes a row away to leave the conversation. Both
/// need surface iOS does not have yet.
struct ChatsListView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<ChatsList>

    var body: some View {
        WithPerceptionTracking {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    ZappScreenHeader(title: String(localizable: .chatListTitle)) {
                        ChatsConnectionChip(messagingState: store.messagingState)
                    }

                    if !store.isLoaded {
                        loading
                    } else if store.conversations.isEmpty {
                        emptyState
                    } else {
                        conversations
                    }
                }

                ZappFab(icon: Asset.Assets.Icons.messageChat.image, contentDescription: String(localizable: .chatListNewChat)) {
                    store.send(.newConversationTapped)
                }
                .padding(.trailing, Design.Spacing._2xl)
                .padding(.bottom, ZappNavBar.fabBottomPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .onAppear { store.send(.onAppear) }
            .onDisappear { store.send(.onDisappear) }
        }
    }

    private var conversations: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.sortedConversations) { conversation in
                    ChatConversationRow(
                        conversation: conversation,
                        displayName: store.state.displayName(for: conversation),
                        isPeerOnline: store.state.messagingState.isPeerOnline(in: conversation.id),
                        unreadCount: store.state.messagingState.unreadCount(for: conversation.id)
                    ) {
                        store.send(.conversationTapped(conversation.id))
                    }

                    if conversation.id != store.sortedConversations.last?.id {
                        ZappRowDivider(inset: true)
                    }
                }
            }
            .padding(.top, Design.Spacing._xs)
            .padding(.bottom, ZappNavBar.clearance)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Design.Spacing._sm) {
            Text(String(localizable: .chatListEmptyTitle))
                .zappFont(.sectionTitle, style: ZappColors.text)

            Text(String(localizable: .chatListEmptySubtitle))
                .zappFont(.body, style: ZappColors.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Design.Spacing._4xl)
        .padding(.bottom, ZappNavBar.clearance)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loading: some View {
        ProgressView()
            .tint(ZappColors.accent.color(colorScheme))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Silent while the network is healthy: the chip exists to report trouble, not to reassure.
private struct ChatsConnectionChip: View {
    let messagingState: ZappMessagingState

    var body: some View {
        if let status {
            ZappStatusChip(text: status.text, variant: status.variant)
        }
    }
}

private extension ChatsConnectionChip {
    var status: (text: String, variant: ZappChipVariant)? {
        if messagingState.phase == .initializing {
            return (String(localizable: .chatListConnecting), .accent)
        }

        if !messagingState.isOnline {
            return (String(localizable: .chatListOffline), .danger)
        }

        if messagingState.dhtHealth == "degraded" || messagingState.dhtHealth == "critical" {
            return (String(localizable: .chatListDegraded), .accent)
        }

        return nil
    }
}

#Preview {
    ChatsListView(store: ChatsList.initial)
}
