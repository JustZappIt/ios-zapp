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
    @Environment(\.scenePhase) private var scenePhase

    private enum Constants {
        static let width: CGFloat = 280
        static let padding: CGFloat = 12
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
    var readReceiptsEnabled: Bool

    @StateObject private var gifPlayer = ChatGIFPlayer()
    @State private var image: UIImage?
    @State private var isThumbnail = false
    @State private var didFail = false

    private var isFromMe: Bool { message.isFromMe }
    private var isGIF: Bool { message.contentType == "image/gif" }

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
        .onDisappear {
            gifPlayer.stop()
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active, isGIF, let path = message.mediaLocalPath else {
                gifPlayer.stop()
                return
            }

            gifPlayer.play(path: path)
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
        .accessibilityLabel(String(localizable: isGIF ? .chatRoomGif : .chatRoomPhoto))
    }

    @ViewBuilder
    private var imageLayer: some View {
        if let frame = gifPlayer.frame {
            Image(decorative: frame, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(width: Constants.width, height: height)
        } else if let image {
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
                    readColor: ZappColors.accent.color(colorScheme)
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

    // A media bubble is neutral in both directions: the picture carries the row, and an accent
    // panel around an outgoing photo fights it. Matches `MediaBubble.kt`.
    private var bubbleColor: Color {
        ZappColors.surfaceAlt.color(colorScheme)
    }

    private var textColor: Color {
        ZappColors.text.color(colorScheme)
    }

    private var metaColor: Color {
        ZappColors.textMuted.color(colorScheme)
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

        guard !Task.isCancelled else { return }

        image = decoded?.0
        isThumbnail = decoded?.1 ?? false

        // Only a file we were told is on disk can "fail". No file yet is a transfer in flight.
        didFail = decoded == nil && path != nil

        if scenePhase == .active, isGIF, let path {
            gifPlayer.play(path: path)
        } else {
            gifPlayer.stop()
        }
    }
}

/// Streams one downsampled GIF frame at a time. ImageIO's animation convenience API returns
/// source-resolution frames on the main queue, so a compact 4K GIF can otherwise consume tens
/// of megabytes per visible row. Decoding each requested frame to the bubble's pixel budget keeps
/// playback memory constant and lets cancellation stop off-screen work immediately.
@MainActor
final class ChatGIFPlayer: ObservableObject {
    @Published private(set) var frame: CGImage?

    private var playbackTask: Task<Void, Never>?
    private var currentPath: String?

    func play(path: String) {
        guard currentPath != path || playbackTask == nil else { return }

        stop()
        currentPath = path

        playbackTask = Task { [weak self] in
            guard let descriptor = await ChatGIFDecoder.descriptor(path: path) else { return }

            var index = 0

            while !Task.isCancelled {
                guard let decoded = await ChatGIFDecoder.frame(path: path, index: index) else { return }
                guard !Task.isCancelled, self?.currentPath == path else { return }

                self?.frame = decoded.image

                do {
                    try await Task.sleep(for: .seconds(descriptor.delays[index]))
                } catch {
                    return
                }

                index = (index + 1) % descriptor.delays.count
            }
        }
    }

    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        currentPath = nil
        frame = nil
    }
}

private enum ChatGIFDecoder {
    struct Descriptor: Sendable {
        let delays: [Double]
    }

    struct Frame: @unchecked Sendable {
        let image: CGImage
    }

    private static let maxFileBytes = 16 * 1024 * 1024
    private static let maxFrames = 300
    private static let maxPixel: CGFloat = 560
    private static let defaultDelay = 0.1
    private static let minimumDelay = 0.05
    private static let maximumDelay = 10.0

    static func descriptor(path: String) async -> Descriptor? {
        await Task.detached(priority: .userInitiated) {
            autoreleasepool {
                let url = URL(fileURLWithPath: path)

                guard
                    ChatMediaImage.fileByteCount(at: url).map({ $0 <= maxFileBytes }) == true,
                    ChatMediaImage.isGIF(at: url),
                    let source = CGImageSourceCreateWithURL(url as CFURL, ChatMediaImage.sourceOptions)
                else {
                    return nil
                }

                let count = CGImageSourceGetCount(source)
                guard count > 1, count <= maxFrames else { return nil }

                var delays: [Double] = []
                delays.reserveCapacity(count)

                for index in 0..<count {
                    guard ChatMediaImage.sourceIsWithinPixelLimit(source, index: index) else { return nil }

                    let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
                    let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
                    let rawDelay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
                        ?? (gif?[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue
                        ?? defaultDelay
                    let finiteDelay = rawDelay.isFinite ? rawDelay : defaultDelay
                    delays.append(min(max(finiteDelay, minimumDelay), maximumDelay))
                }

                return Descriptor(delays: delays)
            }
        }
        .value
    }

    static func frame(path: String, index: Int) async -> Frame? {
        await Task.detached(priority: .userInitiated) {
            autoreleasepool {
                guard let image = ChatMediaImage.downsampledCGImage(
                    path: path,
                    index: index,
                    maxPixel: maxPixel
                ) else {
                    return nil
                }

                return Frame(image: image)
            }
        }
        .value
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
    /// Mirrors Android's bounds-only guard. Downsampling controls the output allocation;
    /// this limit rejects malformed inputs whose declared canvas is itself unreasonable.
    private static let maxSourcePixels: Int64 = 100_000_000

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

    /// GIF87a / GIF89a. The picker's declared types describe the asset, not these bytes.
    static func isGIF(_ data: Data) -> Bool {
        data.count >= 6 && data.prefix(6).elementsEqual(Array("GIF89a".utf8))
            || data.count >= 6 && data.prefix(6).elementsEqual(Array("GIF87a".utf8))
    }

    static func isGIF(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }

        guard let signature = try? handle.read(upToCount: 6) else { return false }

        return isGIF(signature)
    }

    static func fileByteCount(at url: URL) -> Int? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]), let size = values.fileSize else {
            return nil
        }

        return size
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

    static var sourceOptions: CFDictionary {
        [kCGImageSourceShouldCache: false] as CFDictionary
    }

    static func sourceIsWithinPixelLimit(_ source: CGImageSource, index: Int) -> Bool {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.int64Value,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.int64Value,
            width > 0,
            height > 0,
            width <= maxSourcePixels / height
        else {
            return false
        }

        return width * height <= maxSourcePixels
    }

    static func downsampledCGImage(path: String, index: Int, maxPixel: CGFloat) -> CGImage? {
        guard
            maxPixel.isFinite,
            maxPixel > 0,
            let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, sourceOptions),
            index >= 0,
            index < CGImageSourceGetCount(source),
            sourceIsWithinPixelLimit(source, index: index)
        else {
            return nil
        }

        return downsampledCGImage(source: source, index: index, maxPixel: maxPixel)
    }

    private static func downsampled(source: CGImageSource, maxPixel: CGFloat) -> UIImage? {
        guard sourceIsWithinPixelLimit(source, index: 0) else { return nil }

        guard let image = downsampledCGImage(source: source, index: 0, maxPixel: maxPixel) else { return nil }

        return UIImage(cgImage: image)
    }

    private static func downsampledCGImage(source: CGImageSource, index: Int, maxPixel: CGFloat) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]

        return CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
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
            senderName: "satoshi",
            readReceiptsEnabled: true
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
            progress: 0.4,
            readReceiptsEnabled: true
        )
    }
    .padding(16)
    .applyScreenBackground()
}
