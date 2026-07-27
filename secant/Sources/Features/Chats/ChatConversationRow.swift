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
            Asset.Assets.Icons.users.image
                .zImage(width: Constants.avatarIconSize, height: Constants.avatarIconSize, style: ZappColors.onAccent)
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
        ChatPreviewSentinel.previewText(for: conversation)
    }
}

/// The iOS "peek" shown while long-pressing a chat row — Appendix C.1, approved for this phase.
///
/// iOS-only: Android's list has no equivalent affordance, so there is nothing to match pixel for
/// pixel. It is built from the data the list already holds (`ZMConversation`), never by loading the
/// room — a peek must not open a conversation stream the user has not committed to.
struct ChatConversationPreviewCard: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let width: CGFloat = 300
        static let avatarSize: CGFloat = 40
        static let avatarIconSize: CGFloat = 18
        static let presenceSize: CGFloat = 8
        static let presenceBorder: CGFloat = 2
        static let accentBarWidth: CGFloat = 3
        static let messageMinHeight: CGFloat = 64
    }

    let conversation: ZMConversation
    let displayName: String
    var isPeerOnline = false
    var unreadCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Rectangle()
                .fill(ZappColors.border.color(colorScheme))
                .frame(height: 1)

            message
        }
        .frame(width: Constants.width, alignment: .leading)
        .background(ZappColors.surface.color(colorScheme))
    }

    private var header: some View {
        HStack(spacing: Design.Spacing._lg) {
            ZStack(alignment: .bottomTrailing) {
                ZStack { avatarContent }
                    .frame(width: Constants.avatarSize, height: Constants.avatarSize)
                    .background(ZappColors.accent.color(colorScheme))

                if isPeerOnline && conversation.type == .direct {
                    Rectangle()
                        .fill(ZappColors.success.color(colorScheme))
                        .frame(width: Constants.presenceSize, height: Constants.presenceSize)
                        .padding(Constants.presenceBorder)
                        .background(ZappColors.surface.color(colorScheme))
                }
            }

            VStack(alignment: .leading, spacing: Design.Spacing._xxs) {
                Text(displayName)
                    .zappFont(.rowTitle, style: ZappColors.text)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let subtitle {
                    Text(subtitle)
                        .zappFont(.caption, style: ZappColors.textSubtle)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(Design.Spacing._lg)
    }

    /// The accent rule on the leading edge is the same device the Receive warning and the
    /// transaction rows use to mark quoted content — no bubble, no rounded corner.
    private var message: some View {
        HStack(alignment: .top, spacing: Design.Spacing._md) {
            Rectangle()
                .fill(ZappColors.accent.color(colorScheme))
                .frame(width: Constants.accentBarWidth)

            Text(ChatPreviewSentinel.previewText(for: conversation))
                .zappFont(.body, style: ZappColors.textMuted)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Design.Spacing._lg)
        .frame(minHeight: Constants.messageMinHeight, alignment: .top)
    }

    private var subtitle: String? {
        if unreadCount > 0 {
            return String(localizable: .chatListPreviewUnread(String(unreadCount)))
        }

        return conversation.lastMessageTimestamp.map { ChatRelativeTime.label(for: $0) }
    }

    @ViewBuilder
    private var avatarContent: some View {
        let initials = displayName.zappInitials

        if conversation.type == .group {
            Asset.Assets.Icons.users.image
                .zImage(width: Constants.avatarIconSize, height: Constants.avatarIconSize, style: ZappColors.onAccent)
        } else if initials.trimmingCharacters(in: .whitespaces).isEmpty {
            Asset.Assets.Icons.user.image
                .zImage(width: Constants.avatarIconSize, height: Constants.avatarIconSize, style: ZappColors.onAccent)
        } else {
            Text(initials)
                .zappFont(.rowTitle, style: ZappColors.onAccent)
        }
    }
}

/// Previews written by the JS core, mirroring `ChatListVM.lastMessageText` /
/// `ChatConversationsRepository`'s sentinels one-for-one: every content type gets its own label
/// rather than collapsing into a single "Photo".
enum ChatPreviewSentinel {
    /// The one place a conversation turns into a human-readable last line, shared by the row and
    /// its context-menu peek so the two can never disagree.
    static func previewText(for conversation: ZMConversation) -> String {
        guard let lastMessage = conversation.lastMessage else {
            return String(localizable: .chatListNoMessages)
        }

        return label(for: lastMessage) ?? jsonLabel(for: lastMessage) ?? lastMessage
    }

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
