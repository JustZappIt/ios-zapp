//
//  ChatTransactionBubble.swift
//  Zapp
//
//  Android's `view/bubbles/TransactionBubble.kt` — the receipt posted after a successful
//  chat-initiated send (`SubmitProposalUseCase.notifyChatPeer`). Tapping it opens the local
//  transaction detail, which is only possible when the tx is in this wallet: the id comes from
//  a peer, so the room checks before it navigates.
//

import SwiftUI
import ZappMessaging

struct ChatTransactionBubble: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let maxWidth: CGFloat = 280
        static let padding: CGFloat = 12
        static let icon: CGFloat = 18
        static let backgroundOpacity: CGFloat = 0.1
        static let signaturePrefix = 8
        static let signatureSuffix = 4
    }

    let message: ZMMessage
    var senderName: String?
    var onViewTransaction: ((String) -> Void)?
    var readReceiptsEnabled = true

    private var isFromMe: Bool { message.isFromMe }

    private var receipt: ChatTransactionReceipt {
        ChatTransactionReceipt.parse(message.content)
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
        let receipt = self.receipt
        let txId = receipt.txId

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Design.Spacing._md) {
                Asset.Assets.Icons.checkVerifiedFilled.image
                    .zImage(width: Constants.icon, height: Constants.icon, style: ZappColors.accent)

                Text(
                    isFromMe
                        ? String(localizable: .chatBubbleTransactionSent)
                        : String(localizable: .chatBubbleTransactionReceived)
                )
                .zappFont(.caption, style: ZappColors.accent)
            }

            Text("\(ChatAmountFormat.zec(receipt.amount)) \(receipt.token)")
                .zappFont(.rowTitle, style: ZappColors.text)
                .padding(.top, Design.Spacing._md)

            if let signature = receipt.signature {
                Text(String(localizable: .chatBubbleTransactionSignature(
                    String(signature.prefix(Constants.signaturePrefix)),
                    String(signature.suffix(Constants.signatureSuffix))
                )))
                .zappFont(.caption, style: ZappColors.textMuted)
                .padding(.top, Design.Spacing._xs)
            }

            HStack(alignment: .firstTextBaseline, spacing: Design.Spacing._xs) {
                Text(ChatBubbleTime.label(for: message.timestamp))
                    .zappFont(.caption, style: ZappColors.textMuted)

                if isFromMe {
                    ChatMessageStatusIndicator(
                        status: ChatMessageStatusIndicator.Status(wire: message.status)
                            .visible(readReceiptsEnabled: readReceiptsEnabled),
                        mutedColor: ZappColors.textMuted.color(colorScheme),
                        readColor: ZappColors.accent.color(colorScheme)
                    )
                }
            }
            .padding(.top, Design.Spacing._xs)
        }
        .padding(Constants.padding)
        .frame(maxWidth: Constants.maxWidth, alignment: .leading)
        .background(ZappColors.accent.color(colorScheme).opacity(Constants.backgroundOpacity))
        .contentShape(Rectangle())
        .onTapGesture {
            if let txId { onViewTransaction?(txId) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(txId != nil && onViewTransaction != nil ? .isButton : [])
    }
}

#Preview {
    let receipt = ChatTransactionReceipt.json(
        amount: Decimal(string: "0.42") ?? 0,
        requestId: "req-1",
        txId: "abc123"
    ) ?? ""

    return VStack(spacing: 8) {
        ChatTransactionBubble(
            message: ZMMessage(
                id: "1",
                conversationId: "c",
                senderId: "me",
                content: receipt,
                contentType: ChatContentType.zecTransaction,
                isFromMe: true,
                status: "sent"
            ),
            onViewTransaction: { _ in }
        )

        ChatTransactionBubble(
            message: ZMMessage(
                id: "2",
                conversationId: "c",
                senderId: "peer",
                content: receipt,
                contentType: ChatContentType.zecTransaction,
                isFromMe: false
            ),
            senderName: "satoshi"
        )
    }
    .padding(16)
    .applyScreenBackground()
}
