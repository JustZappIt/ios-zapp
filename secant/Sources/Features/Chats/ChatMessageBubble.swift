//
//  ChatMessageBubble.swift
//  Zapp
//

import SwiftUI
import ZappMessaging

struct ChatMessageBubble: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let maxWidth: CGFloat = 280
        static let padding: CGFloat = 12
        static let outgoingMetaOpacity: CGFloat = 0.7
        static let quoteBarWidth: CGFloat = 3
        static let quoteBarHeight: CGFloat = 36
        static let quoteTopPadding: CGFloat = 8
        static let quoteBottomPadding: CGFloat = 6
    }

    let message: ZMMessage

    private var isFromMe: Bool { message.isFromMe }
    private var hasQuote: Bool { message.replyToId != nil }

    var body: some View {
        VStack(alignment: isFromMe ? .trailing : .leading, spacing: Design.Spacing._xxs) {
            if !isFromMe, let senderName = message.senderName {
                Text(senderName)
                    .zappFont(.chip, style: ZappColors.accent)
                    .padding(.leading, Design.Spacing._xs)
            }

            if hasQuote {
                VStack(spacing: 0) {
                    quote
                    bubble
                }
            } else {
                bubble
            }
        }
        .frame(maxWidth: Constants.maxWidth, alignment: isFromMe ? .trailing : .leading)
        .frame(maxWidth: .infinity, alignment: isFromMe ? .trailing : .leading)
    }

    /// A quoted bubble fills the group's width so the quote block and the message share one edge.
    private var fillWidth: CGFloat? { hasQuote ? .infinity : nil }

    private var bubble: some View {
        // Baseline-aligned, not bottom-aligned: the meta is 10pt against 14pt body
        // text, so matching box edges leaves the time floating above the words.
        // Aligning on the LAST baseline sits it on the final line of the message,
        // which is where a reader expects it.
        HStack(alignment: .lastTextBaseline, spacing: Design.Spacing._md) {
            Text(message.content)
                .zappFont(.body, color: textColor)
                .frame(maxWidth: fillWidth, alignment: .leading)

            meta
        }
        .padding(Constants.padding)
        .frame(maxWidth: fillWidth, alignment: .leading)
        .background(bubbleColor)
    }

    /// Time, then the tick — always in that order, and the tick is always last so
    /// it stays hard against the bubble's trailing edge.
    private var meta: some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Spacing._xs) {
            Text(timeLabel)
                .zappFont(.bubbleMeta, color: metaColor)
                .fixedSize()

            if isFromMe {
                ChatMessageStatusIndicator(
                    status: .init(wire: message.status),
                    mutedColor: metaColor,
                    readColor: ZappColors.onAccent.color(colorScheme)
                )
            }
        }
        .fixedSize()
    }

    private var quote: some View {
        HStack(spacing: Design.Spacing._md) {
            Rectangle()
                .fill(ZappColors.accent.color(colorScheme))
                .frame(width: Constants.quoteBarWidth, height: Constants.quoteBarHeight)

            VStack(alignment: .leading, spacing: 0) {
                if let senderName = message.replyToSenderName {
                    Text(senderName)
                        .zappFont(.chip, style: ZappColors.accent)
                        .lineLimit(1)
                }

                Text(message.replyToContent ?? "")
                    .zappFont(.caption, style: ZappColors.textMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Constants.padding)
        .padding(.top, Constants.quoteTopPadding)
        .padding(.bottom, Constants.quoteBottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ZappColors.surfaceInput.color(colorScheme))
    }

    private var bubbleColor: Color {
        isFromMe
            ? ZappColors.accent.color(colorScheme)
            : ZappColors.surfaceAlt.color(colorScheme)
    }

    private var textColor: Color {
        isFromMe
            ? ZappColors.onAccent.color(colorScheme)
            : ZappColors.text.color(colorScheme)
    }

    private var metaColor: Color {
        isFromMe
            ? ZappColors.onAccent.color(colorScheme).opacity(Constants.outgoingMetaOpacity)
            : ZappColors.textMuted.color(colorScheme)
    }

    private var timeLabel: String {
        ChatBubbleTime.label(for: message.timestamp)
    }
}

private extension ZappTextStyle {
    static let bubbleMeta = ZappTextStyle(weight: .medium, size: 10, lineHeight: 16)
}

#Preview {
    VStack(spacing: 8) {
        ChatMessageBubble(
            message: ZMMessage(
                id: "1",
                conversationId: "c",
                senderId: "peer",
                senderName: "satoshi",
                content: "Sharp corners only.",
                isFromMe: false
            )
        )

        ChatMessageBubble(
            message: ZMMessage(
                id: "2",
                conversationId: "c",
                senderId: "me",
                content: "Read receipts land as a double tick.",
                isFromMe: true,
                status: "read"
            )
        )

        ChatMessageBubble(
            message: ZMMessage(
                id: "3",
                conversationId: "c",
                senderId: "me",
                content: "Quoted.",
                isFromMe: true,
                status: "queued",
                replyToId: "1",
                replyToSenderName: "satoshi",
                replyToContent: "Sharp corners only."
            )
        )
    }
    .padding(16)
    .applyScreenBackground()
}

/// A fixed `HH:mm` format is not 24-hour unless the locale is pinned: under a
/// 12-hour regional preference the device locale renders "2:42 PM". `ChatRelativeTime`
/// pins it for the same reason, and the two clocks must agree on one screen.
enum ChatBubbleTime {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func label(for date: Date) -> String {
        formatter.string(from: date)
    }
}
