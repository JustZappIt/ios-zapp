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
                        ChatNetworkStatusChip(state: store.messagingState, context: .list) {
                            store.send(.networkChipTapped)
                        }
                    }

                    if !store.isLoaded {
                        loading
                    } else if store.conversations.isEmpty {
                        emptyState
                    } else {
                        conversations
                    }
                }

                ZappFab(icon: Asset.Assets.Icons.messageChat.image, accessibilityLabel: String(localizable: .chatListNewChat)) {
                    store.send(.newConversationTapped)
                }
                .padding(.trailing, Design.Spacing._2xl)
                .padding(.bottom, ZappNavBar.fabBottomPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .onAppear { store.send(.onAppear) }
            .onDisappear { store.send(.onDisappear) }
            .sheet(
                isPresented: Binding(
                    get: { store.showsNetworkDetails },
                    set: { if !$0 { store.send(.networkDetailsDismissed) } }
                )
            ) {
                ChatNetworkDetailsView(
                    state: store.messagingState,
                    details: store.connectionDetails,
                    isLoading: store.isLoadingNetworkDetails,
                    onRefresh: { store.send(.networkChipTapped) }
                )
            }
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
                    .contextMenu {
                        if conversation.type == .direct {
                            Button(String(localizable: .generalDelete), role: .destructive) {
                                store.send(.removeConversationTapped(conversation.id))
                            }
                        }
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

#Preview {
    ChatsListView(store: ChatsList.initial)
}
