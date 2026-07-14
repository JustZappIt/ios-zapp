//
//  ChatReplyBar.swift
//  Zapp
//

import SwiftUI

/// The staged reply, above the composer. The quote that ships *on* a sent message is drawn by
/// `ChatMessageBubble`; this is only what the user is about to answer.
struct ChatReplyBar: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let accentBarWidth: CGFloat = 3
        static let cancelSize: CGFloat = 44
    }

    let senderName: String
    let content: String
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: Design.Spacing._md) {
            Rectangle()
                .fill(ZappColors.accent.color(colorScheme))
                .frame(width: Constants.accentBarWidth)

            VStack(alignment: .leading, spacing: Design.Spacing._xxs) {
                Text("\(String(localizable: .chatRoomReplyingTo)) \(senderName)")
                    .zappFont(.chip, style: ZappColors.accent)
                    .lineLimit(1)

                Text(content)
                    .zappFont(.caption, style: ZappColors.textMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onCancel) {
                Text(verbatim: "×")
                    .zappFont(.cancelGlyph, style: ZappColors.textMuted)
                    .frame(width: Constants.cancelSize, height: Constants.cancelSize)
            }
            .buttonStyle(.zappPress)
            .accessibilityLabel(String(localizable: .chatRoomCancelReply))
        }
        .padding(.leading, Design.Spacing._xl)
        .padding(.vertical, Design.Spacing._md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ZappColors.surfaceInput.color(colorScheme))
    }
}

private extension ZappTextStyle {
    static let cancelGlyph = ZappTextStyle(weight: .medium, size: 22, lineHeight: 24)
}

#Preview {
    ChatReplyBar(
        senderName: "satoshi",
        content: "Sharp corners only.",
        onCancel: { }
    )
    .applyScreenBackground()
}
