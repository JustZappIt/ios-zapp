//
//  ChatLocationBubble.swift
//  Zapp
//
//  Android's `view/bubbles/LocationBubble.kt`, receive side only: iOS cannot share a location
//  yet, but one sent from Android renders as a location rather than as its raw JSON.
//

import SwiftUI
import ZappMessaging

/// The `application/location` body: `{"latitude": …, "longitude": …}`. Android reads it with
/// `optDouble`, so a missing or malformed coordinate is 0 rather than a failed row.
struct ChatLocation: Equatable {
    let latitude: Double
    let longitude: Double

    static func parse(_ content: String) -> ChatLocation {
        let object = ChatMessageJSON.object(content)

        return ChatLocation(
            latitude: (object?["latitude"] as? NSNumber)?.doubleValue ?? 0,
            longitude: (object?["longitude"] as? NSNumber)?.doubleValue ?? 0
        )
    }

    /// Android's `"%.6f, %.6f"` under `Locale.US`.
    var coordinates: String {
        String(format: "%.6f, %.6f", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude)
    }

    /// Apple Maps in place of Android's `geo:` intent.
    var mapsURL: URL? {
        URL(string: "https://maps.apple.com/?ll=\(latitude),\(longitude)&q=\(latitude),\(longitude)")
    }
}

struct ChatLocationBubble: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    private enum Constants {
        static let maxWidth: CGFloat = 280
        static let padding: CGFloat = 12
        static let backgroundOpacity: CGFloat = 0.1
    }

    let message: ZMMessage
    var senderName: String?
    var readReceiptsEnabled = true

    private var isFromMe: Bool { message.isFromMe }

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
        let location = ChatLocation.parse(message.content)

        return VStack(alignment: .leading, spacing: Design.Spacing._md) {
            Text(
                isFromMe
                    ? String(localizable: .chatBubbleLocationShared)
                    : String(localizable: .chatBubbleLocationReceived)
            )
            .zappFont(.caption, style: ZappColors.accent)

            Text(location.coordinates)
                .zappFont(.body, style: ZappColors.text)
                .textSelection(.enabled)

            Button {
                if let url = location.mapsURL {
                    openURL(url)
                }
            } label: {
                HStack(spacing: Design.Spacing._xs) {
                    Asset.Assets.Icons.arrowRight.image
                        .zImage(width: 14, height: 14, style: ZappColors.accent)

                    Text(String(localizable: .chatBubbleLocationOpenInMaps))
                        .zappFont(.caption, style: ZappColors.accent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.zappPress)

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
        }
        .padding(Constants.padding)
        .frame(maxWidth: Constants.maxWidth, alignment: .leading)
        .background(ZappColors.accent.color(colorScheme).opacity(Constants.backgroundOpacity))
    }
}

#Preview {
    ChatLocationBubble(
        message: ZMMessage(
            id: "1",
            conversationId: "c",
            senderId: "peer",
            content: #"{"latitude":40.7128,"longitude":-74.006}"#,
            contentType: ChatContentType.location,
            isFromMe: false
        ),
        senderName: "satoshi"
    )
    .padding(16)
    .applyScreenBackground()
}
