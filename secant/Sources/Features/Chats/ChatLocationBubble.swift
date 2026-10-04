//
//  ChatLocationBubble.swift
//  Zapp
//
//  Android's `view/bubbles/LocationBubble.kt`: an accent-tinted panel with a pin and
//  "Location shared"/"Location received", the coordinates to six decimals, an "Open in Maps"
//  link, then the time and delivery status.
//
//  Like Android, no map image is drawn. A map snapshot would send every received coordinate to
//  Apple's tile servers as soon as the row scrolled into view; opening Maps stays a deliberate tap.
//

import SwiftUI
import ZappMessaging

struct ChatLocationBubble: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    private enum Constants {
        static let maxWidth: CGFloat = 280
        static let padding: CGFloat = 12
        static let headerIcon: CGFloat = 18
    }

    let message: ZMMessage
    let location: ChatLocation
    var senderName: String?
    var readReceiptsEnabled = true

    private var isFromMe: Bool { message.isFromMe }

    private var title: String {
        isFromMe
            ? String(localizable: .chatBubbleLocationShared)
            : String(localizable: .chatBubbleLocationReceived)
    }

    var body: some View {
        VStack(alignment: isFromMe ? .trailing : .leading, spacing: Design.Spacing._xxs) {
            if !isFromMe, let senderName {
                Text(senderName)
                    .zappFont(.chip, style: ZappColors.accent)
                    .padding(.leading, Design.Spacing._xs)
            }

            Button {
                if let url = location.mapsURL {
                    openURL(url)
                }
            } label: {
                card
            }
            .buttonStyle(.zappPress)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(title), \(location.coordinateText)"))
            .accessibilityHint(String(localizable: .chatBubbleLocationOpenInMaps))
            .accessibilityAddTraits(.isButton)
        }
        .frame(maxWidth: .infinity, alignment: isFromMe ? .trailing : .leading)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Design.Spacing._sm) {
                Asset.Assets.Icons.markerPin.image
                    .zImage(width: Constants.headerIcon, height: Constants.headerIcon, style: ZappColors.accent)

                Text(title)
                    .zappFont(.caption, style: ZappColors.accent)
            }

            Text(location.coordinateText)
                .zappFont(.body, style: ZappColors.text)
                .padding(.top, Design.Spacing._sm)

            // Android leads this with an "open in new" glyph the Zashi set has no equivalent for.
            Text(String(localizable: .chatBubbleLocationOpenInMaps))
                .zappFont(.caption, style: ZappColors.accent)
                .padding(.top, Design.Spacing._sm)

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
        .background(ZappColors.accentSoft.color(colorScheme))
    }
}

#Preview {
    VStack(spacing: 8) {
        ChatLocationBubble(
            message: ZMMessage(
                id: "1",
                conversationId: "c",
                senderId: "peer",
                senderName: "satoshi",
                content: #"{"latitude":37.7749,"longitude":-122.4194,"accuracy":20}"#,
                contentType: ChatContentType.location,
                isFromMe: false
            ),
            location: ChatLocation(latitude: 37.7749, longitude: -122.4194, accuracy: 20),
            senderName: "satoshi"
        )

        ChatLocationBubble(
            message: ZMMessage(
                id: "2",
                conversationId: "c",
                senderId: "me",
                content: #"{"latitude":51.5007,"longitude":-0.1246,"accuracy":8}"#,
                contentType: ChatContentType.location,
                isFromMe: true,
                status: "delivered"
            ),
            location: ChatLocation(latitude: 51.5007, longitude: -0.1246, accuracy: 8)
        )
    }
    .padding(16)
    .applyScreenBackground()
}
