//
//  ChatLinkPreviewCard.swift
//  Zapp
//

import SwiftUI

/// The resolved link card. Used twice: staged above the composer while typing, and attached
/// under the bubble once the message is sent.
struct ChatLinkPreviewCard: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let accentBarWidth: CGFloat = 3
        static let imageSize: CGFloat = 52
        static let cancelSize: CGFloat = 44
    }

    let preview: ChatLinkPreview
    var onCancel: (() -> Void)?

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
    }

    private var image: UIImage? {
        preview.imageData.flatMap { ChatMediaImage.downsampled(data: $0, maxPixel: Constants.imageSize * 3) }
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
