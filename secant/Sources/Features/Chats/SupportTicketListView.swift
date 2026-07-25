//
//  SupportTicketListView.swift
//  Zapp
//
//  Mirrors `screen/chat/support/SupportTicketListScreen.kt`.
//

import ComposableArchitecture
import SwiftUI

struct SupportTicketListView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<SupportTicketList>

    var body: some View {
        WithPerceptionTracking {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    ZappScreenHeader(title: String(localizable: .supportChatTitle)) {
                        ZappBackButton { store.send(.backTapped) }
                    } right: {
                        EmptyView()
                    }

                    if !store.isLoaded {
                        loading
                    } else if store.tickets.isEmpty {
                        emptyState
                    } else {
                        tickets
                    }
                }

                ZappFab(
                    icon: Asset.Assets.Icons.plus.image,
                    accessibilityLabel: String(localizable: .supportTicketListNew)
                ) {
                    store.send(.newTicketTapped)
                }
                .padding(.trailing, Design.Spacing._2xl)
                .padding(.bottom, ZappNavBar.pushedFloatingMargin)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .zappSwipeBack { store.send(.backTapped) }
            .onAppear { store.send(.onAppear) }
            .onDisappear { store.send(.onDisappear) }
            .alert($store.scope(state: \.alert, action: \.alert))
        }
    }

    private var tickets: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.tickets) { ticket in
                    // Android reveals a "Close" action on the same swipe the chat list uses to
                    // leave a conversation.
                    ChatSwipeToRevealRow(
                        identity: ticket.conversationId,
                        actionLabel: String(localizable: .generalClose),
                        onAction: { store.send(.closeTicketRequested(ticket.conversationId)) },
                        content: { tap in
                            SupportTicketRow(ticket: ticket, action: tap)
                                .contextMenu {
                                    Button(String(localizable: .generalClose), role: .destructive) {
                                        store.send(.closeTicketRequested(ticket.conversationId))
                                    }
                                }
                        },
                        onTap: { store.send(.ticketTapped(ticket.conversationId)) }
                    )

                    if ticket.id != store.tickets.last?.id {
                        ZappRowDivider(inset: true)
                    }
                }
            }
            .padding(.top, Design.Spacing._xs)
            .padding(.bottom, ZappNavBar.pushedFloatingMargin)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Design.Spacing._sm) {
            Asset.Assets.Icons.noMessage.image
                .zImage(width: Constants.emptyIconSize, height: Constants.emptyIconSize, style: ZappColors.textSubtle)

            Text(String(localizable: .supportTicketListEmptyTitle))
                .zappFont(.sectionTitle, style: ZappColors.text)

            Text(String(localizable: .supportTicketListEmptySubtitle))
                .zappFont(.body, style: ZappColors.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Design.Spacing._4xl)
        .padding(.bottom, ZappNavBar.pushedFloatingMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loading: some View {
        ProgressView()
            .tint(ZappColors.accent.color(colorScheme))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private enum Constants {
        static let emptyIconSize: CGFloat = 56
    }
}

/// One ticket row. Deliberately shaped like `ChatConversationRow`: a ticket IS a conversation, and
/// Android draws it with the same avatar / title / time / subtitle / unread-chip skeleton.
private struct SupportTicketRow: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let avatarSize: CGFloat = 44
        static let horizontalPadding: CGFloat = 14
        static let verticalPadding: CGFloat = 12
        static let spacing: CGFloat = 12
    }

    let ticket: SupportTicketList.Ticket
    let action: () -> Void

    var body: some View {
        Button(action: action) { row }
            .buttonStyle(.zappPress)
    }

    private var row: some View {
        HStack(spacing: Constants.spacing) {
            Text(initial)
                .zappFont(.sectionTitle, style: ZappColors.onAccent)
                .frame(width: Constants.avatarSize, height: Constants.avatarSize)
                .background(ZappColors.accent.color(colorScheme))

            VStack(alignment: .leading, spacing: Design.Spacing._xxs) {
                HStack(spacing: Design.Spacing._md) {
                    Text(ticket.categoryLabel)
                        .zappFont(.rowTitle, style: ZappColors.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let timeLabel = ticket.timeLabel {
                        Text(timeLabel)
                            .zappFont(.caption, style: ZappColors.textSubtle)
                    }
                }

                HStack(spacing: Design.Spacing._md) {
                    Text(ticket.lastMessage ?? String(localizable: .chatListNoMessages))
                        .zappFont(.rowSubtitle, style: ZappColors.textMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if ticket.unreadCount > 0 {
                        Text("\(ticket.unreadCount)")
                            .zappFont(.chip, style: ZappColors.onAccent)
                            .padding(.horizontal, Design.Spacing._sm)
                            .padding(.vertical, Design.Spacing._xxs)
                            .background(ZappColors.accent.color(colorScheme))
                    }
                }
            }
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.vertical, Constants.verticalPadding)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    /// Android renders the topic's first character in the avatar square.
    private var initial: String {
        ticket.categoryLabel.first.map { String($0).uppercased() } ?? ""
    }
}

#Preview {
    SupportTicketListView(store: SupportTicketList.initial)
}
