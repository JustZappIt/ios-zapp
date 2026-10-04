//
//  ChatVideoBubble.swift
//  Zapp
//
//  Android's `view/bubbles/MediaBubble.kt` for a `video/*` message: a poster (the first frame of
//  the transferred file, else the wire thumbnail, else a "Video" placeholder), a play glyph once
//  there is nothing in flight, the transfer progress, then the caption, time and status.
//
//  One deliberate difference: Android draws the play glyph but never handles the tap (03-chats Q7).
//  Here the row opens `ChatVideoPlayer` once the file is on disk.
//

import AVFoundation
import SwiftUI
import UIKit
import ZappMessaging

struct ChatVideoBubble: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let width: CGFloat = 280
        static let padding: CGFloat = 12
        static let defaultAspect: CGFloat = 16.0 / 9.0
        static let minAspect: CGFloat = 0.6
        static let maxAspect: CGFloat = 2.0
        static let placeholderBlur: CGFloat = 8
        static let progressBarHeight: CGFloat = 3
        static let playIcon: CGFloat = 48
        static let playOpacity: CGFloat = 0.85
        /// Twice the rendered width, the same budget as a photo bubble.
        static let posterMaxPixel: CGFloat = 560
    }

    let message: ZMMessage
    var senderName: String?
    /// `nil` unless a transfer is in flight. Supplied by the room.
    var progress: Double?
    var readReceiptsEnabled: Bool

    @State private var poster: UIImage?
    @State private var isThumbnail = false
    @State private var didFail = false

    private var isFromMe: Bool { message.isFromMe }

    private var showsPlay: Bool {
        progress == nil && message.status != "sending" && !didFail
    }

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
            .background(ZappColors.surfaceAlt.color(colorScheme))
        }
        .frame(maxWidth: Constants.width, alignment: isFromMe ? .trailing : .leading)
        .frame(maxWidth: .infinity, alignment: isFromMe ? .trailing : .leading)
        .task(id: message.mediaLocalPath) {
            await load()
        }
    }

    private var media: some View {
        ZStack {
            posterLayer

            if showsPlay {
                Asset.Assets.Icons.playCircle.image
                    .zImage(width: Constants.playIcon, height: Constants.playIcon, style: ZappColors.text)
                    .opacity(Constants.playOpacity)
            }

            if let progress {
                Rectangle()
                    .fill(ZappColors.overlay.color(colorScheme))

                progressBar(progress)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(width: Constants.width, height: height)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localizable: .chatRoomVideo))
        .accessibilityHint(playHint)
    }

    private var playHint: String {
        showsPlay && ChatVideoPlayback.fileURL(for: message) != nil
            ? String(localizable: .chatRoomPlayVideo)
            : ""
    }

    @ViewBuilder
    private var posterLayer: some View {
        if let poster {
            Image(uiImage: poster)
                .resizable()
                .scaledToFill()
                .frame(width: Constants.width, height: height)
                .blur(radius: isThumbnail ? Constants.placeholderBlur : 0)
        } else {
            Rectangle()
                .fill(ZappColors.surfaceAlt.color(colorScheme))
                .overlay(
                    Text(String(localizable: didFail ? .chatRoomVideoFailed : .chatRoomVideo))
                        .zappFont(.caption, style: ZappColors.textMuted)
                        .padding(.top, didFail ? 0 : Constants.playIcon + Design.Spacing._md)
                )
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
                    .zappFont(.body, style: ZappColors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .firstTextBaseline, spacing: Design.Spacing._xs) {
                Text(ChatBubbleTime.label(for: message.timestamp))
                    .zappFont(.mediaMeta, style: ZappColors.textMuted)
                    .fixedSize()

                if isFromMe {
                    ChatMessageStatusIndicator(
                        status: ChatMessageStatusIndicator.Status(wire: message.status)
                            .visible(readReceiptsEnabled: readReceiptsEnabled),
                        mutedColor: ZappColors.textMuted.color(colorScheme),
                        readColor: ZappColors.accent.color(colorScheme)
                    )
                }
            }
            .fixedSize()
        }
        .padding(Constants.padding)
    }

    /// The wire carries no dimensions for a video, so the poster sets the shape once it exists.
    private var height: CGFloat {
        let aspect: CGFloat

        if
            let width = message.mediaWidth,
            let height = message.mediaHeight,
            width > 0,
            height > 0 {
            aspect = CGFloat(width) / CGFloat(height)
        } else if let poster, poster.size.height > 0 {
            aspect = poster.size.width / poster.size.height
        } else {
            aspect = Constants.defaultAspect
        }

        return Constants.width / min(max(aspect, Constants.minAspect), Constants.maxAspect)
    }

    private func load() async {
        let fileURL = ChatVideoPlayback.fileURL(for: message)
        let thumbnailData = message.thumbnailData

        var frame: CGImage?
        if let fileURL {
            frame = await ChatVideoFrame.first(of: AVURLAsset(url: fileURL), maxPixel: Constants.posterMaxPixel)
        }

        guard !Task.isCancelled else { return }

        if let frame {
            poster = UIImage(cgImage: frame)
            isThumbnail = false
        } else {
            poster = await Task.detached(priority: .userInitiated) {
                ChatMediaImage.decodeThumbnail(thumbnailData)
            }
            .value
            isThumbnail = poster != nil
        }

        // Only a file we were told is on disk can "fail". No file yet is a transfer in flight.
        didFail = fileURL != nil && frame == nil
    }
}

/// Whether a video message has something to play, and where.
enum ChatVideoPlayback {
    static func fileURL(for message: ZMMessage) -> URL? {
        guard let path = message.mediaLocalPath, FileManager.default.fileExists(atPath: path) else { return nil }

        return URL(fileURLWithPath: path)
    }
}

#Preview {
    VStack(spacing: 8) {
        ChatVideoBubble(
            message: ZMMessage(
                id: "1",
                conversationId: "c",
                senderId: "peer",
                senderName: "satoshi",
                content: "",
                contentType: "video/mp4",
                isFromMe: false,
                mediaId: "m1"
            ),
            senderName: "satoshi",
            readReceiptsEnabled: true
        )

        ChatVideoBubble(
            message: ZMMessage(
                id: "2",
                conversationId: "c",
                senderId: "me",
                content: "",
                contentType: "video/mp4",
                isFromMe: true,
                mediaId: "m2",
                status: "queued"
            ),
            progress: 0.4,
            readReceiptsEnabled: true
        )
    }
    .padding(16)
    .applyScreenBackground()
}
