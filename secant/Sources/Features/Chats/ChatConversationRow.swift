//
//  ChatConversationRow.swift
//  Zapp
//

import SwiftUI
import ZappMessaging

/// One conversation in the Chats tab, mirroring `ChatListConversationItem.kt`.
///
/// `isPeerOnline` and `unreadCount` are passed in rather than read off the conversation: the SDK
/// carries per-peer status and per-conversation unread, but `ZappMessagingClient` surfaces neither
/// yet (only a total unread), so the list passes `false` / `0` until it does.
struct ChatConversationRow: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let avatarSize: CGFloat = 44
        static let avatarIconSize: CGFloat = 20
        static let presenceSize: CGFloat = 8
        static let presenceBorder: CGFloat = 2
        static let horizontalPadding: CGFloat = 14
        static let verticalPadding: CGFloat = 12
        static let spacing: CGFloat = 12
    }

    let conversation: ZMConversation
    /// Resolved by the store (local alias > wire name > key prefix). The row must
    /// not read `conversation.displayName` directly, or a saved alias never shows.
    let displayName: String
    var isPeerOnline = false
    var unreadCount = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) { row }
            .buttonStyle(.zappPress)
    }

    private var row: some View {
        HStack(spacing: Constants.spacing) {
            avatar

            VStack(alignment: .leading, spacing: Design.Spacing._xxs) {
                HStack(spacing: Design.Spacing._md) {
                    Text(displayName)
                        .zappFont(.rowTitle, style: ZappColors.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let timeLabel {
                        Text(timeLabel)
                            .zappFont(.caption, style: ZappColors.textSubtle)
                    }
                }

                HStack(spacing: Design.Spacing._md) {
                    Text(preview)
                        .zappFont(.rowSubtitle, style: ZappColors.textMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if unreadCount > 0 {
                        Text("\(unreadCount)")
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

    private var avatar: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                if let iconName = avatarIconName {
                    Image(systemName: iconName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: Constants.avatarIconSize, height: Constants.avatarIconSize)
                        .zForegroundColor(ZappColors.onAccent)
                } else {
                    Text(initials)
                        .zappFont(.rowTitle, style: ZappColors.onAccent)
                }
            }
            .frame(width: Constants.avatarSize, height: Constants.avatarSize)
            .background(ZappColors.accent.color(colorScheme))

            if isPeerOnline && conversation.type == .direct {
                Rectangle()
                    .fill(ZappColors.success.color(colorScheme))
                    .frame(width: Constants.presenceSize, height: Constants.presenceSize)
                    .padding(Constants.presenceBorder)
                    .background(ZappColors.bg.color(colorScheme))
            }
        }
    }

    private var initials: String {
        displayName.zappInitials
    }

    private var avatarIconName: String? {
        if conversation.type == .group {
            return "person.2.fill"
        }

        return initials.trimmingCharacters(in: .whitespaces).isEmpty ? "person.fill" : nil
    }

    private var timeLabel: String? {
        conversation.lastMessageTimestamp.map { ChatRelativeTime.label(for: $0) }
    }

    private var preview: String {
        guard let lastMessage = conversation.lastMessage else {
            return String(localizable: .chatListNoMessages)
        }

        if ChatPreviewSentinel.media.contains(lastMessage) {
            return String(localizable: .chatListMediaPlaceholder)
        }

        if ChatPreviewSentinel.payment.contains(lastMessage) || lastMessage.hasPrefix("{") {
            return String(localizable: .chatListPaymentPlaceholder)
        }

        return lastMessage
    }
}

/// Previews written by the JS core. A cold load hands back the raw JSON body of a structured
/// message, which must never reach the user as JSON.
private enum ChatPreviewSentinel {
    static let media: Set<String> = ["[Media]", "[Photo]", "[Video]", "[File]", "[Location]", "[GIF]"]
    static let payment: Set<String> = ["[Payment]", "[PaymentRequest]"]
}

#Preview {
    VStack(spacing: 0) {
        ChatConversationRow(
            conversation: ZMConversation(
                id: "1",
                type: .direct,
                participantIds: [],
                displayName: "chinmay",
                lastMessage: "See you at 8",
                lastMessageTimestamp: Date()
            ),
            displayName: "chinmay",
            isPeerOnline: true,
            unreadCount: 3
        ) { }

        ZappRowDivider(inset: true)

        ChatConversationRow(
            conversation: ZMConversation(
                id: "2",
                type: .group,
                participantIds: [],
                displayName: "Zapp builders",
                lastMessage: "{\"txId\":\"abc\"}",
                lastMessageTimestamp: Date(timeIntervalSinceNow: -7200)
            ),
            displayName: "Zapp builders"
        ) { }

        ZappRowDivider(inset: true)

        ChatConversationRow(
            conversation: ZMConversation(id: "3", type: .direct, participantIds: [], displayName: "ada"),
            displayName: "ada"
        ) { }
    }
    .applyScreenBackground()
}
