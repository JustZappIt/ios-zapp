//
//  ChatsListView.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI
import ZappMessaging

/// The Chats tab root, mirroring `ChatListView.kt`.
///
/// Android also pins an aggregate "Zapp Support" row above the list; that arrives with the support
/// subsystem in Phase 7, alongside the sorting extension point marked in `ChatsListStore`.
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
            // Swiping the sheet away is the analogue of Android's `onDismissRequest`, which declines.
            .sheet(
                isPresented: Binding(
                    get: { store.showsTermsDialog },
                    set: { if !$0 { store.send(.termsDeclined) } }
                )
            ) {
                ChatTermsView(
                    onAccept: { store.send(.termsAccepted) },
                    onDecline: { store.send(.termsDeclined) }
                )
            }
            .alert($store.scope(state: \.alert, action: \.alert))
        }
    }

    private var conversations: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.sortedConversations) { conversation in
                    // Android swipes both direct and group rows away to leave; the context menu
                    // stays as the discoverable, accessible route to the same action.
                    ChatSwipeToLeaveRow(
                        conversation: conversation,
                        onLeave: { store.send(.leaveConversationRequested(conversation.id)) },
                        onTap: { store.send(.conversationTapped(conversation.id)) }
                    ) { tap in
                        ChatConversationRow(
                            conversation: conversation,
                            displayName: store.state.displayName(for: conversation),
                            isPeerOnline: store.state.messagingState.isPeerOnline(in: conversation.id),
                            unreadCount: store.state.messagingState.unreadCount(for: conversation.id),
                            action: tap
                        )
                        .contextMenu {
                            Button(String(localizable: .chatListLeaveAction), role: .destructive) {
                                store.send(.leaveConversationRequested(conversation.id))
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
