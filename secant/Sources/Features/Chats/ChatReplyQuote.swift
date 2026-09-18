//
//  ChatReplyQuote.swift
//  Zapp
//
//  What a reply says about the message it quotes. The summary and type it puts ON THE WIRE
//  (`replyToContent`, `replyToContentType`) are derived here, and so is the label, icon and
//  thumbnail a quote block draws from them. Android's `ChatReplyQuote.kt` is the mirror: the two
//  clients read each other's quotes through the same kind table.
//

import SwiftUI
import UIKit
import ZappMessaging

// MARK: - Kind

/// What a quoted message renders as, derived from the `replyToContentType` a reply carries.
/// `.text` is also the reading of a reply from a client that predates the field.
enum ChatReplyQuoteKind: Equatable {
    case text
    case photo
    case gif
    case video
    case file
    case paymentRequest
    case transaction
    case walletAddress
    case location

    init(contentType: String?) {
        guard let contentType, !contentType.isEmpty, contentType != ChatContentType.text else {
            self = .text
            return
        }

        switch contentType {
        case ChatContentType.paymentRequest: self = .paymentRequest
        case ChatContentType.walletAddress: self = .walletAddress
        case ChatContentType.zecTransaction: self = .transaction
        case ChatContentType.location: self = .location
        case ChatContentType.gif: self = .gif
        default:
            if contentType.hasPrefix(ChatContentType.imagePrefix) {
                self = .photo
            } else if contentType.hasPrefix(ChatContentType.videoPrefix) {
                self = .video
            } else {
                self = .file
            }
        }
    }

    /// Only a quoted picture has something to thumbnail.
    var showsThumbnail: Bool {
        self == .photo || self == .gif || self == .video
    }

    /// `nil` for text, which shows its content alone.
    var label: String? {
        switch self {
        case .text: return nil
        case .photo: return String(localizable: .chatRoomReplyKindPhoto)
        case .gif: return String(localizable: .chatRoomReplyKindGIF)
        case .video: return String(localizable: .chatRoomReplyKindVideo)
        case .file: return String(localizable: .chatRoomReplyKindFile)
        case .paymentRequest: return String(localizable: .chatRoomReplyKindPaymentRequest)
        case .transaction: return String(localizable: .chatRoomReplyKindTransaction)
        case .walletAddress: return String(localizable: .chatRoomReplyKindWalletAddress)
        case .location: return String(localizable: .chatRoomReplyKindLocation)
        }
    }

    /// The catalogue has no location glyph, so that kind is named by its label alone.
    var icon: Image? {
        switch self {
        case .text, .location: return nil
        case .photo, .gif, .video: return Asset.Assets.Icons.imageLibrary.image
        case .file: return Asset.Assets.Icons.file.image
        case .paymentRequest: return Asset.Assets.Icons.pay.image
        case .transaction: return Asset.Assets.Icons.currencyZec.image
        case .walletAddress: return Asset.Assets.Icons.connectWallet.image
        }
    }
}

// MARK: - Wire summary

enum ChatReplyPreview {
    /// Mirrors Android's `REPLY_WIRE_CONTENT_MAX_LENGTH` and the SDK's own preview cap.
    static let maxLength = 100

    /// The `replyToContentType` a reply carries: the quoted message's resolved MIME type. A file
    /// attachment whose type resolves to `text/plain` (a `.txt`) is labelled as a file, not as
    /// text, so the quote never reads a filename as a sentence.
    static func wireContentType(for message: ZMMessage) -> String {
        let resolved = ChatMessageKind.resolvedContentType(of: message)

        if ChatMessageKind.of(message) == .file, resolved == ChatContentType.text {
            return "application/octet-stream"
        }

        return resolved
    }

    /// The `replyToContent` a reply carries: a one-line summary of the quoted message, never its
    /// raw body. A client that predates `replyToContentType` renders this line verbatim, so it has
    /// to read on its own; a newer one prefixes it with the label for its kind. Text keeps its
    /// text, media its caption, a file its name and an address its address; a payment request or
    /// transaction becomes its amount and a location its coordinates.
    static func wireContent(for message: ZMMessage) -> String {
        let summary: String

        switch ChatMessageKind.of(message) {
        case .paymentRequest:
            let request = ChatPaymentRequest.parse(message.content)
            summary = zecSummary(amount: request.amount, memo: request.memo, fallback: message.content)

        case .zecTransaction:
            let receipt = ChatTransactionReceipt.parse(message.content)
            summary = zecSummary(amount: receipt.amount, memo: nil, fallback: message.content)

        case .walletAddress, .image, .video, .file, .text:
            if ChatMessageKind.resolvedContentType(of: message) == ChatContentType.location {
                summary = locationSummary(message.content)
            } else {
                summary = message.content
            }
        }

        return String(summary.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
    }

    /// The single line under the sender name in a quote block: the kind's label, the quoted
    /// content, or both joined by a middle dot.
    static func line(kind: ChatReplyQuoteKind, content: String?) -> String {
        let body = (content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard let label = kind.label else { return body }

        return body.isEmpty ? label : "\(label) · \(body)"
    }

    private static func zecSummary(amount: Decimal, memo: String?, fallback: String) -> String {
        guard amount > 0 else { return fallback }

        let zec = "\(ChatAmountFormat.zec(amount)) ZEC"

        if let memo, !memo.isEmpty { return "\(zec) · \(memo)" }

        return zec
    }

    /// Android's `LocationBubble` renders `%.6f, %.6f` in `Locale.US`; the quote says the same.
    private static func locationSummary(_ content: String) -> String {
        let object = ChatMessageJSON.object(content)

        guard
            let latitude = ChatMessageJSON.decimal(in: object, "latitude"),
            let longitude = ChatMessageJSON.decimal(in: object, "longitude")
        else {
            return content
        }

        return String(
            format: "%.6f, %.6f",
            locale: Locale(identifier: "en_US_POSIX"),
            NSDecimalNumber(decimal: latitude).doubleValue,
            NSDecimalNumber(decimal: longitude).doubleValue
        )
    }
}

// MARK: - Views

/// The icon-and-text line of a quote, shared by the quote block on a sent reply and the staged
/// reply above the composer.
struct ChatReplyQuoteLine: View {
    private enum Constants {
        static let icon: CGFloat = 14
    }

    let kind: ChatReplyQuoteKind
    let content: String?

    var body: some View {
        HStack(spacing: Design.Spacing._xs) {
            if let icon = kind.icon {
                icon.zImage(width: Constants.icon, height: Constants.icon, style: ZappColors.textMuted)
            }

            Text(ChatReplyPreview.line(kind: kind, content: content))
                .zappFont(.caption, style: ZappColors.textMuted)
                .lineLimit(1)
        }
    }
}

/// The small picture beside a quoted photo, GIF or video. Degrades like `ChatMediaBubble`: the
/// local file, else the wire thumbnail, else nothing (the label still names the kind).
struct ChatReplyQuoteThumbnail: View {
    let message: ZMMessage
    var size: CGFloat = 36

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
            }
        }
        .task(id: message.mediaLocalPath) {
            await load()
        }
    }

    /// Decodes off the main actor for the same reason the media bubble does: a photo decoded
    /// inline would hitch the scroll on every quoting row.
    private func load() async {
        let path = message.mediaLocalPath
        let thumbnailData = message.thumbnailData
        let maxPixel = size * UIScreen.main.scale

        let decoded = await Task.detached(priority: .utility) { () -> UIImage? in
            if let path, let full = ChatMediaImage.downsampled(path: path, maxPixel: maxPixel) {
                return full
            }

            return ChatMediaImage.decodeThumbnail(thumbnailData)
        }
        .value

        guard !Task.isCancelled else { return }

        image = decoded
    }
}
