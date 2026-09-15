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
//  Takes values rather than reading the store, and is `Equatable`, so a row only re-renders
//  when something of its own changed — not on every peer-count tick or preview in the room.
//

import ComposableArchitecture
import SwiftUI
import UIKit
import ZappMessaging

struct ChatRoomBubbleRow: View, @MainActor Equatable {
    private enum Constants {
        /// Matches the media bubble, so a link card and a photo line up on the same edge.
        static let linkPreviewWidth: CGFloat = 280
    }

    let store: StoreOf<ChatRoom>

    let message: ZMMessage
    let senderName: String?
    /// Read receipts are reciprocal: with them off, a `read` status is shown as merely
    /// `delivered`, on every bubble kind rather than only the text and media ones.
    let readReceiptsEnabled: Bool
    let localPublicKey: String?
    let fiatRate: ChatFiatRate?
    let linkPreview: ChatLinkPreview?
    let progress: Double?
    let isPaid: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.store === rhs.store
            && lhs.message == rhs.message
            && lhs.senderName == rhs.senderName
            && lhs.readReceiptsEnabled == rhs.readReceiptsEnabled
            && lhs.localPublicKey == rhs.localPublicKey
            && lhs.fiatRate == rhs.fiatRate
            && lhs.linkPreview == rhs.linkPreview
            && lhs.progress == rhs.progress
            && lhs.isPaid == rhs.isPaid
    }

    var body: some View {
        bubble
            .contentShape(Rectangle())
            .onAppear {
                // Drives the link-preview fetch; only a text message with a URL needs the round trip.
                if kind == .text, ChatLinkPreviewParser.firstWebURL(in: message.content) != nil {
                    store.send(.messageAppeared(message))
                }
            }
            .onTapGesture {
                handleTap()
            }
            .contextMenu {
                contextMenu
            }
    }

    private var kind: ChatMessageKind { ChatMessageKind.of(message) }

    /// One bubble per message type, dispatched in Android's order
    /// (`ChatMessageBubble.kt: MessageContent`) via `ChatMessageKind`. Anything unrecognised —
    /// including location, out of scope per Decision 3 — falls through to the text bubble.
    @ViewBuilder
    private var bubble: some View {
        switch kind {
        case .paymentRequest:
            ChatPaymentRequestBubble(
                message: message,
                senderName: senderName,
                localPublicKey: localPublicKey,
                fiatRate: fiatRate,
                isPaid: isPaid,
                onPay: { store.send(.payRequestTapped(message)) }
            )

        case .walletAddress:
            ChatWalletAddressBubble(
                message: message,
                senderName: senderName,
                onCopy: { store.send(.copyAddressTapped($0)) },
                onSendToAddress: { store.send(.sendToAddressTapped($0)) },
                readReceiptsEnabled: readReceiptsEnabled
            )

        case .zecTransaction:
            ChatTransactionBubble(
                message: message,
                senderName: senderName,
                onViewTransaction: { store.send(.viewTransactionTapped($0)) },
                readReceiptsEnabled: readReceiptsEnabled
            )

        case .image, .video:
            ChatMediaBubble(
                message: message,
                senderName: senderName,
                progress: progress,
                readReceiptsEnabled: readReceiptsEnabled
            )

        case .file:
            ChatFileBubble(
                message: message,
                senderName: senderName,
                progress: progress,
                readReceiptsEnabled: readReceiptsEnabled
            )

        case .text:
            VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: Design.Spacing._xxs) {
                ChatMessageBubble(
                    message: message,
                    senderName: senderName,
                    readReceiptsEnabled: readReceiptsEnabled
                )

                if let preview = linkPreview {
                    ChatLinkPreviewCard(preview: preview)
                        .frame(maxWidth: Constants.linkPreviewWidth)
                }
            }
            .frame(maxWidth: .infinity, alignment: message.isFromMe ? .trailing : .leading)
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
            ZappHaptics.impact()
            store.send(.replyTapped(message))
        }

        if let copyable = copyableText {
            Button(String(localizable: .newChatCopy)) {
                store.send(.copyAddressTapped(copyable))
            }
        }
    }

    /// A failed message retries; an image opens fullscreen. Android guards the image tap the same
    /// way — a still-sending picture has nothing to show at full size yet.
    private func handleTap() {
        if message.isFromMe && message.status == "failed" {
            store.send(.retrySendTapped(message))
            return
        }

        if kind == .image && message.status != "sending" {
            store.send(.imageTapped(message))
        }
    }

    /// Text bubbles copy their body; a wallet-address bubble copies the address it renders
    /// rather than a JSON wrapper. Structured payloads have no user-meaningful text to copy.
    private var copyableText: String? {
        switch kind {
        case .text:
            return message.content.isEmpty ? nil : message.content

        case .walletAddress:
            return ChatMessageJSON.string(message.content, "content") ?? message.content

        default:
            return nil
        }
    }
}
