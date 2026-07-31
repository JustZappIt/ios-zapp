//
//  ChatMediaBubble.swift
//  Zapp
//

import ImageIO
import SwiftUI
import UIKit
import ZappMessaging

/// A message carrying an image. The full picture only exists once the transfer lands, so the
/// bubble degrades: local file -> the wire thumbnail, blurred -> a neutral box.
struct ChatMediaBubble: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let width: CGFloat = 280
        static let padding: CGFloat = 12
        static let outgoingMetaOpacity: CGFloat = 0.7
        static let defaultAspect: CGFloat = 4.0 / 3.0
        static let minAspect: CGFloat = 0.6
        static let maxAspect: CGFloat = 2.0
        static let placeholderBlur: CGFloat = 8
        static let progressBarHeight: CGFloat = 3

        /// Twice the rendered width: enough for a Retina bubble, and nowhere near the full
        /// 12 MP bitmap a phone photo would otherwise pin in memory per row.
        static let decodeMaxPixel: CGFloat = 560
    }

    let message: ZMMessage
    /// Resolved by the store (local alias > wire name).
    var senderName: String?
    /// `nil` unless a transfer is in flight. Supplied by the room — the bubble owns no streams.
    var progress: Double?
    /// Read receipts are reciprocal. The stored status remains read, but the bubble only
    /// highlights it while receipts are enabled.
    var readReceiptsEnabled = true

    @State private var image: UIImage?
    @State private var isThumbnail = false
    @State private var didFail = false

    private var isFromMe: Bool { message.isFromMe }

    var body: some View {
        VStack(alignment: isFromMe ? .trailing : .leading, spacing: Design.Spacing._xxs) {
            if !isFromMe, let senderName {
                Text(senderName)
                    .zappFont(.chip, style: ZappColors.accent)
                    .padding(.leading, Design.Spacing._xs)
            }

            VStack(spacing: 0) {
                media
                footer
            }
            .frame(width: Constants.width)
            .background(bubbleColor)
        }
        .frame(maxWidth: Constants.width, alignment: isFromMe ? .trailing : .leading)
        .frame(maxWidth: .infinity, alignment: isFromMe ? .trailing : .leading)
        .task(id: message.mediaLocalPath) {
            await load()
        }
    }

    private var media: some View {
        ZStack(alignment: .bottom) {
            imageLayer

            if let progress {
                Rectangle()
                    .fill(ZappColors.overlay.color(colorScheme))

                progressBar(progress)
            }
        }
        .frame(width: Constants.width, height: height)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localizable: .chatRoomPhoto))
    }

    @ViewBuilder
    private var imageLayer: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: Constants.width, height: height)
                .blur(radius: isThumbnail ? Constants.placeholderBlur : 0)
        } else if didFail {
            Rectangle()
                .fill(ZappColors.surfaceAlt.color(colorScheme))
                .overlay(
                    Text(String(localizable: .chatRoomImageFailed))
                        .zappFont(.caption, style: ZappColors.textMuted)
                )
        } else {
            Rectangle()
                .fill(ZappColors.surfaceAlt.color(colorScheme))
        }
    }

    private func progressBar(_ progress: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(ZappColors.borderStrong.color(colorScheme))

                Rectangle()
                    .fill(ZappColors.accent.color(colorScheme))
                    .frame(width: geometry.size.width * CGFloat(min(max(progress, 0), 1)))
            }
        }
        .frame(height: Constants.progressBarHeight)
    }

    private var footer: some View {
        HStack(alignment: .lastTextBaseline, spacing: Design.Spacing._md) {
            if message.content.isEmpty {
                Spacer(minLength: 0)
            } else {
                Text(message.content)
                    .zappFont(.body, color: textColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            meta
        }
        .padding(Constants.padding)
    }

    private var meta: some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Spacing._xs) {
            Text(ChatBubbleTime.label(for: message.timestamp))
                .zappFont(.mediaMeta, color: metaColor)
                .fixedSize()

            if isFromMe {
                ChatMessageStatusIndicator(
                    status: ChatMessageStatusIndicator.Status(wire: message.status)
                        .visible(readReceiptsEnabled: readReceiptsEnabled),
                    mutedColor: metaColor,
                    readColor: ZappColors.onAccent.color(colorScheme)
                )
            }
        }
        .fixedSize()
    }

    /// The declared dimensions come off the wire, so a placeholder holds the right shape before a
    /// single byte of the image has landed. Clamped: a panorama must not become a 3000pt row.
    private var height: CGFloat {
        let aspect: CGFloat

        if
            let width = message.mediaWidth,
            let height = message.mediaHeight,
            width > 0,
            height > 0 {
            aspect = CGFloat(width) / CGFloat(height)
        } else if let image, image.size.height > 0 {
            aspect = image.size.width / image.size.height
        } else {
            aspect = Constants.defaultAspect
        }

        return Constants.width / min(max(aspect, Constants.minAspect), Constants.maxAspect)
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

    /// Decoding runs off the main actor: a full-size JPEG decoded inline would hitch the scroll
    /// on every row that comes into view.
    private func load() async {
        let path = message.mediaLocalPath
        let thumbnailData = message.thumbnailData
        let maxPixel = Constants.decodeMaxPixel

        let decoded = await Task.detached(priority: .userInitiated) { () -> (UIImage, Bool)? in
            if let path, let full = ChatMediaImage.downsampled(path: path, maxPixel: maxPixel) {
                return (full, false)
            }

            if let thumbnail = ChatMediaImage.decodeThumbnail(thumbnailData) {
                return (thumbnail, true)
            }

            return nil
        }
        .value

        image = decoded?.0
        isThumbnail = decoded?.1 ?? false

        // Only a file we were told is on disk can "fail". No file yet is a transfer in flight.
        didFail = decoded == nil && path != nil
    }
}

/// ImageIO rather than `UIImage(contentsOfFile:)`: it downsamples during decode, so a 12 MP photo
/// never becomes a 48 MB bitmap on the way to a 280pt bubble.
enum ChatMediaImage {
    /// A peer's thumbnail arrives inside the message body. Cap the encoded length before
    /// allocating anything, so a hostile peer cannot force a multi-MB decode. Mirrors
    /// `ImageProcessor.decodePeerThumbnail` on Android.
    private static let maxThumbnailBase64Chars = 512 * 1024
    private static let thumbnailMaxPixel: CGFloat = 400

    static func decodeThumbnail(_ base64: String?) -> UIImage? {
        guard
            let base64,
            base64.count <= maxThumbnailBase64Chars,
            let data = Data(base64Encoded: base64, options: [.ignoreUnknownCharacters])
        else {
            return nil
        }

        return downsampled(data: data, maxPixel: thumbnailMaxPixel)
    }

    static func downsampled(path: String, maxPixel: CGFloat) -> UIImage? {
        guard
            let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, sourceOptions)
        else {
            return nil
        }

        return downsampled(source: source, maxPixel: maxPixel)
    }

    static func downsampled(data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }

        return downsampled(source: source, maxPixel: maxPixel)
    }

    private static var sourceOptions: CFDictionary {
        [kCGImageSourceShouldCache: false] as CFDictionary
    }

    private static func downsampled(source: CGImageSource, maxPixel: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        return UIImage(cgImage: image)
    }
}

private extension ZappTextStyle {
    static let mediaMeta = ZappTextStyle(weight: .medium, size: 10, lineHeight: 16)
}

#Preview {
    VStack(spacing: 8) {
        ChatMediaBubble(
            message: ZMMessage(
                id: "1",
                conversationId: "c",
                senderId: "peer",
                senderName: "satoshi",
                content: "Sharp corners, even here.",
                contentType: "image/jpeg",
                isFromMe: false,
                mediaId: "m1",
                mediaWidth: 1200,
                mediaHeight: 900
            ),
            senderName: "satoshi"
        )

        ChatMediaBubble(
            message: ZMMessage(
                id: "2",
                conversationId: "c",
                senderId: "me",
                content: "",
                contentType: "image/jpeg",
                isFromMe: true,
                mediaId: "m2",
                mediaWidth: 1000,
                mediaHeight: 1000,
                status: "queued"
            ),
            progress: 0.4
        )
    }
    .padding(16)
    .applyScreenBackground()
}
