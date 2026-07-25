//
//  ChatFileBubble.swift
//  Zapp
//
//  Android's `view/bubbles/FileBubble.kt`. The file NAME travels in the message body — that is
//  where `sendFileFromUri` puts it and where Phase 5's `fileImported` sends it as the caption —
//  and the size comes off `mediaSize`.
//

import SwiftUI
import ZappMessaging

struct ChatFileBubble: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let maxWidth: CGFloat = 280
        static let padding: CGFloat = 12
        static let icon: CGFloat = 28
        static let outgoingMetaOpacity: CGFloat = 0.7
        static let progressLineWidth: CGFloat = 2
    }

    let message: ZMMessage
    var senderName: String?
    /// `nil` unless a transfer is in flight — supplied by the room, as with the media bubble.
    var progress: Double?

    private var isFromMe: Bool { message.isFromMe }

    private var fileName: String {
        message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(localizable: .chatRoomMediaFile)
            : message.content
    }

    var body: some View {
        VStack(alignment: isFromMe ? .trailing : .leading, spacing: Design.Spacing._xxs) {
            if !isFromMe, let senderName {
                Text(senderName)
                    .zappFont(.chip, style: ZappColors.accent)
                    .padding(.leading, Design.Spacing._xs)
            }

            card
        }
        .frame(maxWidth: .infinity, alignment: isFromMe ? .trailing : .leading)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Design.Spacing._md) {
                glyph

                VStack(alignment: .leading, spacing: 0) {
                    Text(fileName)
                        .zappFont(.body, color: contentColor)
                        .lineLimit(2)

                    if let size = fileSizeLabel {
                        Text(size)
                            .zappFont(.caption, color: metaColor)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .firstTextBaseline, spacing: Design.Spacing._xs) {
                Text(ChatBubbleTime.label(for: message.timestamp))
                    .zappFont(.caption, color: metaColor)

                if isFromMe {
                    ChatMessageStatusIndicator(
                        status: .init(wire: message.status),
                        mutedColor: metaColor,
                        readColor: ZappColors.onAccent.color(colorScheme)
                    )
                }
            }
            .padding(.top, Design.Spacing._xs)
        }
        .padding(Constants.padding)
        .frame(maxWidth: Constants.maxWidth, alignment: .leading)
        .background(isFromMe ? ZappColors.accent.color(colorScheme) : ZappColors.surfaceAlt.color(colorScheme))
    }

    @ViewBuilder
    private var glyph: some View {
        if let progress {
            // Android swaps the icon for a determinate spinner while bytes are moving.
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(accentOrOnAccent, lineWidth: Constants.progressLineWidth)
                .rotationEffect(.degrees(-90))
                .frame(width: Constants.icon, height: Constants.icon)
        } else {
            Asset.Assets.Icons.file.image
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: Constants.icon, height: Constants.icon)
                .foregroundColor(accentOrOnAccent)
        }
    }

    /// `FileUtils.formatFileSize` — a byte count only shows once it is known and non-zero.
    private var fileSizeLabel: String? {
        guard let size = message.mediaSize, size > 0 else { return nil }

        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    private var contentColor: Color {
        isFromMe ? ZappColors.onAccent.color(colorScheme) : ZappColors.text.color(colorScheme)
    }

    private var metaColor: Color {
        isFromMe
            ? ZappColors.onAccent.color(colorScheme).opacity(Constants.outgoingMetaOpacity)
            : ZappColors.textMuted.color(colorScheme)
    }

    private var accentOrOnAccent: Color {
        isFromMe ? ZappColors.onAccent.color(colorScheme) : ZappColors.accent.color(colorScheme)
    }
}

#Preview {
    VStack(spacing: 8) {
        ChatFileBubble(
            message: ZMMessage(
                id: "1",
                conversationId: "c",
                senderId: "peer",
                content: "whitepaper.pdf",
                contentType: "application/pdf",
                isFromMe: false,
                mediaId: "m1",
                mediaSize: 184_320
            ),
            senderName: "satoshi"
        )

        ChatFileBubble(
            message: ZMMessage(
                id: "2",
                conversationId: "c",
                senderId: "me",
                content: "notes.txt",
                contentType: "text/plain",
                isFromMe: true,
                mediaId: "m2",
                mediaSize: 2048,
                status: "sent"
            ),
            progress: 0.6
        )
    }
    .padding(16)
    .applyScreenBackground()
}
