//
//  ChatRoomBubbleRow.swift
//  Zapp
//
//  One row of the conversation: picks the bubble for the message's type, and owns the tap and
//  long-press affordances that apply to every type.
//
//  Split out of `ChatRoomView` so the room view stays about the SCREEN (header, composer,
//  sheets) and this stays about a MESSAGE — Android draws the same line between `ChatRoomView.kt`
//  and `ChatMessageBubble.kt`.
//

import ComposableArchitecture
import SwiftUI
import UIKit
import ZappMessaging

struct ChatRoomBubbleRow: View {
    @Perception.Bindable var store: StoreOf<ChatRoom>

    let message: ZMMessage

    var body: some View {
        WithPerceptionTracking {
            bubble
                .contentShape(Rectangle())
                .onTapGesture {
                    handleTap()
                }
                .contextMenu {
                    contextMenu
                }
        }
    }

    /// One bubble per message type, dispatched in Android's order
    /// (`ChatMessageBubble.kt: MessageContent`) via `ChatMessageKind`. Anything unrecognised —
    /// including location, out of scope per Decision 3 — falls through to the text bubble.
    @ViewBuilder
    private var bubble: some View {
        switch ChatMessageKind.of(message) {
        case .paymentRequest:
            ChatPaymentRequestBubble(
                message: message,
                senderName: senderName,
                localPublicKey: store.state.localPublicKey,
                fiatRate: store.state.chatFiatRate,
                isPaid: isPaid,
                onPay: { store.send(.payRequestTapped(message)) }
            )

        case .walletAddress:
            ChatWalletAddressBubble(
                message: message,
                senderName: senderName,
                onCopy: { store.send(.copyAddressTapped($0)) },
                onSendToAddress: { store.send(.sendToAddressTapped($0)) }
            )

        case .zecTransaction:
            ChatTransactionBubble(
                message: message,
                senderName: senderName,
                onViewTransaction: { store.send(.viewTransactionTapped($0)) }
            )

        case .image, .video:
            ChatMediaBubble(message: message, senderName: senderName, progress: progress)

        case .file:
            ChatFileBubble(message: message, senderName: senderName, progress: progress)

        case .text:
            ChatMessageBubble(message: message, senderName: senderName)
        }
    }

    /// Reply on every bubble (Android's swipe-to-reply equivalent), plus Copy on the ones that
    /// carry copyable text.
    ///
    /// No haptic fires on the menu OPENING on purpose: `UIContextMenuInteraction` already plays
    /// one when it presents, so Android's explicit LongPress pulse is covered by the platform.
    /// The light impact lands on the reply itself, which is the action Android's haptic
    /// accompanies.
    @ViewBuilder
    private var contextMenu: some View {
        if message.isFromMe && message.status == "failed" {
            Button(String(localizable: .chatRoomRetry)) {
                store.send(.retrySendTapped(message))
            }
        }

        Button(String(localizable: .chatRoomReply)) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            store.send(.replyTapped(message))
        }

        if let copyable = copyableText {
            Button(String(localizable: .newChatCopy)) {
                store.send(.copyAddressTapped(copyable))
            }
        }
    }

    private var senderName: String? {
        store.state.senderName(for: message)
    }

    private var progress: Double? {
        message.mediaId.flatMap { store.mediaProgress[$0] }
    }

    private var isPaid: Bool {
        guard let requestId = ChatPaymentSettlement.requestId(of: message) else { return false }

        return store.state.paidRequestIds.contains(requestId)
    }

    /// A failed message retries; an image opens fullscreen. Android guards the image tap the same
    /// way — a still-sending picture has nothing to show at full size yet.
    private func handleTap() {
        if message.isFromMe && message.status == "failed" {
            store.send(.retrySendTapped(message))
            return
        }

        if ChatMessageKind.of(message) == .image && message.status != "sending" {
            store.send(.imageTapped(message))
        }
    }

    /// Text bubbles copy their body; a wallet-address bubble copies the address it renders
    /// rather than a JSON wrapper. Structured payloads have no user-meaningful text to copy.
    private var copyableText: String? {
        switch ChatMessageKind.of(message) {
        case .text:
            return message.content.isEmpty ? nil : message.content

        case .walletAddress:
            return ChatMessageJSON.string(message.content, "content") ?? message.content

        default:
            return nil
        }
    }
}
