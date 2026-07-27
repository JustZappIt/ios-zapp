//
//  ChatsListView.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI
import ZappMessaging

/// The Chats tab root, mirroring `ChatListView.kt`.
///
/// The aggregate "Zapp Support" row is pinned above the conversations, and stays pinned when there
/// are none — support must be reachable from an empty inbox, which is why the empty state renders
/// beneath the row rather than instead of the whole list.
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
                    } else if store.sortedConversations.isEmpty {
                        supportRow
                        ZappRowDivider(inset: true)
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

    /// Pinned above the timestamp-sorted list, exactly as Android's `item(key = "support_row")`.
    private var supportRow: some View {
        SupportContactRow(
            subtitle: store.state.supportRowSubtitle,
            unreadCount: store.state.supportUnreadCount
        ) {
            store.send(.supportRowTapped)
        }
    }

    private var conversations: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                supportRow
                ZappRowDivider(inset: true)

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
                        // Long-press peeks the conversation before committing to open it
                        // (Appendix C.1). The peek is built from list data only — no room is
                        // opened and no message stream is subscribed to.
                        .contextMenu {
                            Button(String(localizable: .chatListLeaveAction), role: .destructive) {
                                store.send(.leaveConversationRequested(conversation.id))
                            }
                        } preview: {
                            ChatConversationPreviewCard(
                                conversation: conversation,
                                displayName: store.state.displayName(for: conversation),
                                isPeerOnline: store.state.messagingState.isPeerOnline(in: conversation.id),
                                unreadCount: store.state.messagingState.unreadCount(for: conversation.id)
                            )
                        }
                    }

                    // Emitted after EVERY row, including the last — Android's list does the same
                    // (`ZappRowDivider(inset = true)` inside its `items` block), leaving a hairline
                    // above the bottom clearance rather than ending the list on a bare row.
                    ZappRowDivider(inset: true)
                }
            }
            .padding(.top, Design.Spacing._xs)
            .padding(.bottom, ZappNavBar.clearance)
            .zappScrollShadowSource()
        }
        .zappScrollEdges()
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
