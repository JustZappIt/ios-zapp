//
//  ChatConversationRow.swift
//  Zapp
//

import SwiftUI
import ZappMessaging

/// One conversation in the Chats tab, mirroring `ChatListConversationItem.kt`.
///
/// `isPeerOnline` and `unreadCount` are passed in rather than read off the conversation: neither
/// lives on `ZMConversation`. The list reads both off `ZappMessagingState`, keyed by conversation id.
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
                avatarContent
            }
            .frame(width: Constants.avatarSize, height: Constants.avatarSize)
            .background(ZappColors.accent.color(colorScheme))

            // Presence is keyed by conversation, so it only means "someone in here is online".
            // Unambiguous for a DM; meaningless for a group, which therefore gets no dot.
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

    @ViewBuilder
    private var avatarContent: some View {
        if conversation.type == .group {
            // Design-system gap: `Assets.xcassets/Icons` ships `user` but no group glyph, so the
            // group avatar still falls back to a system symbol. Adding a `users` asset is a
            // deliberate design-system extension rather than something to improvise here.
            Image(systemName: "person.2.fill")
                .resizable()
                .scaledToFit()
                .frame(width: Constants.avatarIconSize, height: Constants.avatarIconSize)
                .zForegroundColor(ZappColors.onAccent)
        } else if initials.trimmingCharacters(in: .whitespaces).isEmpty {
            Asset.Assets.Icons.user.image
                .zImage(width: Constants.avatarIconSize, height: Constants.avatarIconSize, style: ZappColors.onAccent)
        } else {
            Text(initials)
                .zappFont(.rowTitle, style: ZappColors.onAccent)
        }
    }

    private var timeLabel: String? {
        conversation.lastMessageTimestamp.map { ChatRelativeTime.label(for: $0) }
    }

    private var preview: String {
        guard let lastMessage = conversation.lastMessage else {
            return String(localizable: .chatListNoMessages)
        }

        return ChatPreviewSentinel.label(for: lastMessage)
            ?? ChatPreviewSentinel.jsonLabel(for: lastMessage)
            ?? lastMessage
    }
}

/// Previews written by the JS core, mirroring `ChatListVM.lastMessageText` /
/// `ChatConversationsRepository`'s sentinels one-for-one: every content type gets its own label
/// rather than collapsing into a single "Photo".
enum ChatPreviewSentinel {
    static func label(for lastMessage: String) -> String? {
        switch lastMessage {
        case "[Media]": return String(localizable: .chatListMediaPlaceholder)
        case "[Photo]": return String(localizable: .chatListPhotoPlaceholder)
        case "[GIF]": return String(localizable: .chatListGifPlaceholder)
        case "[Video]": return String(localizable: .chatListVideoPlaceholder)
        case "[File]": return String(localizable: .chatListFilePlaceholder)
        case "[Location]": return String(localizable: .chatListLocationPlaceholder)
        case "[Payment]": return String(localizable: .chatListPaymentPlaceholder)
        case "[PaymentRequest]": return String(localizable: .chatListPaymentRequestPlaceholder)
        default: return nil
        }
    }

    /// A cold load hands back the raw JSON body of a structured message (the live path already maps
    /// by content type). Mirrors Android's `jsonPreview`, which matches a marker inside the
    /// ~100-character truncation to tell a request from a receipt.
    ///
    /// One deliberate divergence: Android lets an unrecognised JSON body fall through and renders it
    /// verbatim. iOS keeps its existing guarantee that raw JSON never reaches the user and labels it
    /// with the generic payment placeholder instead.
    static func jsonLabel(for lastMessage: String) -> String? {
        guard lastMessage.hasPrefix("{") else { return nil }

        if lastMessage.hasPrefix(paymentRequestPrefix) || lastMessage.contains(paymentRequestAddressMarker) {
            return String(localizable: .chatListPaymentRequestPlaceholder)
        }

        return String(localizable: .chatListPaymentPlaceholder)
    }

    private static let paymentRequestPrefix = "{\"id\":"
    private static let paymentRequestAddressMarker = "\"requesterAddress\""
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
