//
//  ChatWalletAddressBubble.swift
//  Zapp
//
//  Android's `view/bubbles/WalletAddressBubble.kt`. The body is the address VERBATIM — that is
//  what Phase 5's `sendWalletAddress` puts on the wire and what Android's `shareWalletAddress`
//  puts there. A JSON body naming `content` is still accepted, because Android's bubble accepts
//  one too and a peer may have been built that way.
//

import SwiftUI
import ZappMessaging

struct ChatWalletAddressBubble: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let minWidth: CGFloat = 220
        static let maxWidth: CGFloat = 264
        static let headerIcon: CGFloat = 18
        static let copyIcon: CGFloat = 17
        static let copyTarget: CGFloat = 36
        static let qrSize: CGFloat = 136
        static let qrPadding: CGFloat = 7
        static let headerHorizontal: CGFloat = 10
        static let headerVertical: CGFloat = 8
        static let bodyPadding: CGFloat = 12
        static let addressLeading: CGFloat = 9
        static let addressVertical: CGFloat = 7
        static let addressTrailing: CGFloat = 3
        static let sendMinHeight: CGFloat = 44
        static let sendVertical: CGFloat = 10
    }

    let message: ZMMessage
    var senderName: String?
    var onCopy: ((String) -> Void)?
    var onSendToAddress: ((String) -> Void)?

    @State private var didCopy = false

    private var isFromMe: Bool { message.isFromMe }

    /// `JSONObject(content).optString("content", content)` — a JSON body's `content` field, else
    /// the raw body.
    private var address: String {
        ChatMessageJSON.string(message.content, "content") ?? message.content
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
        VStack(spacing: 0) {
            header
            details
        }
        .frame(minWidth: Constants.minWidth, maxWidth: Constants.maxWidth)
        .background(ZappColors.surface.color(colorScheme))
        .overlay {
            Rectangle()
                .strokeBorder(ZappColors.borderStrong.color(colorScheme), lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(spacing: Design.Spacing._sm) {
            Asset.Assets.Icons.connectWallet.image
                .zImage(width: Constants.headerIcon, height: Constants.headerIcon, style: ZappColors.accentText)

            Text(
                (isFromMe
                    ? String(localizable: .chatBubbleWalletAddressShared)
                    : String(localizable: .chatBubbleWalletAddress)
                ).uppercased()
            )
            .zappFont(.eyebrow, style: ZappColors.accentText)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Constants.headerHorizontal)
        .padding(.vertical, Constants.headerVertical)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ZappColors.accentSoft.color(colorScheme))
    }

    private var details: some View {
        VStack(spacing: 0) {
            ChatAddressQRCode(address: address)
                .frame(width: Constants.qrSize, height: Constants.qrSize)
                .padding(Constants.qrPadding)
                .background(Color.white)
                .accessibilityLabel(String(localizable: .chatBubbleWalletQrLabel))

            addressRow
                .padding(.top, Design.Spacing._lg)

            // Android hides Send on your OWN shared address — there is nothing to pay yourself.
            if !isFromMe, let onSendToAddress {
                Button {
                    onSendToAddress(address)
                } label: {
                    Text(String(localizable: .chatBubbleWalletAddressSend))
                        .zappFont(.button, style: ZappColors.onAccent)
                        .padding(.vertical, Constants.sendVertical)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Constants.sendMinHeight)
                        .background(ZappColors.accent.color(colorScheme))
                }
                .buttonStyle(.zappPress)
                .padding(.top, Design.Spacing._md)
            }

            HStack(alignment: .firstTextBaseline, spacing: Design.Spacing._xs) {
                Text(ChatBubbleTime.label(for: message.timestamp))
                    .zappFont(.caption, style: ZappColors.textMuted)

                if isFromMe {
                    ChatMessageStatusIndicator(
                        status: .init(wire: message.status),
                        mutedColor: ZappColors.textMuted.color(colorScheme),
                        readColor: ZappColors.accent.color(colorScheme)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, Design.Spacing._sm)
        }
        .padding(Constants.bodyPadding)
    }

    private var addressRow: some View {
        HStack(spacing: 0) {
            Text(address)
                .zappFont(.mono, style: ZappColors.text)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onCopy?(address)
                didCopy = true
            } label: {
                (didCopy ? Asset.Assets.Icons.checkSolid.image : Asset.Assets.copy.image)
                    .zImage(width: Constants.copyIcon, height: Constants.copyIcon, style: ZappColors.accentText)
                    .frame(width: Constants.copyTarget, height: Constants.copyTarget)
            }
            .buttonStyle(.zappPress)
            .accessibilityLabel(String(localizable: .newChatCopy))
        }
        .padding(.leading, Constants.addressLeading)
        .padding(.trailing, Constants.addressTrailing)
        .padding(.vertical, Constants.addressVertical)
        .background(ZappColors.surfaceAlt.color(colorScheme))
    }
}

/// The bubble's QR. Generated off the main actor like every other QR in the app, and always on a
/// white plate so a dark theme cannot make it unscannable.
private struct ChatAddressQRCode: View {
    let address: String

    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: UIImage(cgImage: image))
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else {
                Rectangle()
                    .fill(Color.white)
            }
        }
        .task(id: address) {
            guard !address.isEmpty else {
                image = nil
                return
            }

            image = await QRCodeGenerator.generate(
                from: address,
                maxPrivacy: false,
                color: .black,
                overlayedWithZcashLogo: false
            )
        }
    }
}

#Preview {
    ChatWalletAddressBubble(
        message: ZMMessage(
            id: "1",
            conversationId: "c",
            senderId: "peer",
            content: "utest1zkkkjfxkamagznjr6ayemffj2d2gacdwpzcyw669pvg06xevzqslpmm27zjsctlkstl2vsw62xrj",
            contentType: ChatContentType.walletAddress,
            isFromMe: false
        ),
        senderName: "satoshi",
        onSendToAddress: { _ in }
    )
    .padding(16)
    .applyScreenBackground()
}
