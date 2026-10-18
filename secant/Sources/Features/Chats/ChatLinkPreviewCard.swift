//
//  ChatLinkPreviewCard.swift
//  Zapp
//

import SwiftUI

/// The resolved link card, staged above the composer while typing. A sent message carries its
/// preview inside the bubble instead (`ChatLinkPreviewBubble`).
struct ChatLinkPreviewCard: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let accentBarWidth: CGFloat = 3
        static let imageSize: CGFloat = 52
        static let cancelSize: CGFloat = 44
    }

    let preview: ChatLinkPreview
    var onCancel: (() -> Void)?

    @State private var image: UIImage?

    var body: some View {
        HStack(spacing: Design.Spacing._md) {
            Rectangle()
                .fill(ZappColors.accent.color(colorScheme))
                .frame(width: Constants.accentBarWidth)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Constants.imageSize, height: Constants.imageSize)
                    .clipped()
            }

            VStack(alignment: .leading, spacing: Design.Spacing._xxs) {
                Text(preview.siteName)
                    .zappFont(.chip, style: ZappColors.accent)
                    .lineLimit(1)

                if let title = preview.title, !title.isEmpty {
                    Text(title)
                        .zappFont(.caption, style: ZappColors.text)
                        .lineLimit(2)
                }

                if let description = preview.description, !description.isEmpty {
                    Text(description)
                        .zappFont(.caption, style: ZappColors.textMuted)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let onCancel {
                Button(action: onCancel) {
                    Text(verbatim: "×")
                        .zappFont(.cancelGlyph, style: ZappColors.textMuted)
                        .frame(width: Constants.cancelSize, height: Constants.cancelSize)
                }
                .buttonStyle(.zappPress)
                .accessibilityLabel(String(localizable: .generalCancel))
            }
        }
        .padding(.leading, Design.Spacing._xl)
        .padding(.vertical, Design.Spacing._md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ZappColors.surfaceInput.color(colorScheme))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localizable: .chatRoomLinkPreviewFrom(preview.siteName)))
        .task(id: preview.imageData) { await load() }
    }

    /// Off the main actor; inline in `body` it re-decoded on every render.
    private func load() async {
        let data = preview.imageData
        let maxPixel = Constants.imageSize * 3

        let decoded = await Task.detached(priority: .userInitiated) {
            data.flatMap { ChatMediaImage.downsampled(data: $0, maxPixel: maxPixel) }
        }
        .value

        guard !Task.isCancelled else { return }

        image = decoded
    }
}

private extension ZappTextStyle {
    static let cancelGlyph = ZappTextStyle(weight: .medium, size: 22, lineHeight: 24)
}

#Preview {
    ChatLinkPreviewCard(
        preview: ChatLinkPreview(
            url: "https://z.cash",
            title: "Zcash",
            description: "Digital cash with privacy built in.",
            siteName: "z.cash",
            imageURL: nil
        ),
        onCancel: { }
    )
    .applyScreenBackground()
}

/// Android's `LinkPreviewBubble`: the sent message's preview, drawn inside its text bubble and
/// opening the link on tap.
struct ChatLinkPreviewBubble: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    private enum Constants {
        static let imageHeight: CGFloat = 132
        static let padding: CGFloat = 10
        static let outgoingBackgroundOpacity: CGFloat = 0.14
        static let outgoingMetaOpacity: CGFloat = 0.74
        static let maxPixel: CGFloat = 840
    }

    let preview: ChatLinkPreview
    let isFromMe: Bool

    @State private var image: UIImage?

    var body: some View {
        Button {
            if let url = URL(string: preview.url) {
                openURL(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                if let image {
                    Color.clear
                        .frame(height: Constants.imageHeight)
                        .frame(maxWidth: .infinity)
                        .overlay {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        }
                        .clipped()
                }

                VStack(alignment: .leading, spacing: Design.Spacing._xxs) {
                    Text(preview.siteName)
                        .zappFont(.caption, color: mutedColor)
                        .lineLimit(1)

                    if let title = preview.title, !title.isEmpty {
                        Text(title)
                            .zappFont(.body, color: foregroundColor)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    if let description = preview.description, !description.isEmpty {
                        Text(description)
                            .zappFont(.caption, color: mutedColor)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding(Constants.padding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(backgroundColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(.zappPress)
        .accessibilityLabel(String(localizable: .chatRoomOpenLink(preview.siteName)))
        .task(id: preview.imageData) { await load() }
    }

    private var foregroundColor: Color {
        isFromMe ? ZappColors.onAccent.color(colorScheme) : ZappColors.text.color(colorScheme)
    }

    private var mutedColor: Color {
        isFromMe
            ? ZappColors.onAccent.color(colorScheme).opacity(Constants.outgoingMetaOpacity)
            : ZappColors.textMuted.color(colorScheme)
    }

    private var backgroundColor: Color {
        isFromMe
            ? ZappColors.onAccent.color(colorScheme).opacity(Constants.outgoingBackgroundOpacity)
            : ZappColors.surfaceInput.color(colorScheme)
    }

    private func load() async {
        let data = preview.imageData
        let maxPixel = Constants.maxPixel

        let decoded = await Task.detached(priority: .userInitiated) {
            data.flatMap { ChatMediaImage.downsampled(data: $0, maxPixel: maxPixel) }
        }
        .value

        guard !Task.isCancelled else { return }

        image = decoded
    }
}
