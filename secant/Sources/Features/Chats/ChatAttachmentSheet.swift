//
//  ChatAttachmentSheet.swift
//  Zapp
//
//  The composer's "+" menu. Mirrors Android's `AttachmentSheet.kt` (four stacked actions,
//  divider between each) and `MediaAttachmentSheet.kt` (title + a row of square tiles).
//
//  Location sharing is deliberately absent from the media page — Decision 3 puts it out of
//  scope, which is the same branch Android takes when `onShareLocation` is null.
//

import ComposableArchitecture
import SwiftUI

/// Page one: share address / send ZEC / split bill / attach media.
struct ChatAttachmentSheet: View {
    private enum Constants {
        static let iconSize: CGFloat = 24
        static let rowVerticalPadding: CGFloat = 16
        static let rowHorizontalPadding: CGFloat = 16
        static let dividerInset: CGFloat = 8
        static let disabledOpacity: CGFloat = 0.4
        static let height: CGFloat = 300
    }

    @Environment(\.colorScheme) private var colorScheme

    let isGroup: Bool
    let onShareAddress: () -> Void
    let onSendZec: () -> Void
    let onSplitBill: () -> Void
    let onAttachMedia: () -> Void

    static var detentHeight: CGFloat { Constants.height }

    var body: some View {
        VStack(spacing: 0) {
            row(
                icon: Asset.Assets.Icons.qr.image,
                label: String(localizable: .chatRoomAttachmentShareAddress),
                action: onShareAddress
            )

            divider

            row(
                icon: Asset.Assets.Icons.sent.image,
                label: String(localizable: .chatRoomAttachmentSendZec),
                action: onSendZec
            )

            divider

            // Android labels this row by conversation type: a group splits a bill, a 1:1 just
            // requests a payment. Both open the same sheet.
            row(
                icon: Asset.Assets.Icons.currencyDollar.image,
                label: isGroup
                    ? String(localizable: .chatRoomAttachmentSplitBill)
                    : String(localizable: .chatRoomAttachmentRequestPayment),
                action: onSplitBill
            )

            divider

            row(
                icon: Asset.Assets.Icons.file.image,
                label: String(localizable: .chatRoomAttachmentAttachMedia),
                action: onAttachMedia
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(ZappColors.border.color(colorScheme))
            .frame(height: 1)
            .padding(.horizontal, Constants.dividerInset)
    }

    private func row(
        icon: Image,
        label: String,
        action: @escaping () -> Void,
        isEnabled: Bool = true
    ) -> some View {
        Button(action: action) {
            // 16pt icon-to-label gap, matching Android's `Arrangement.spacedBy(16.dp)`.
            HStack(spacing: Design.Spacing._xl) {
                icon
                    .zImage(width: Constants.iconSize, height: Constants.iconSize, style: ZappColors.accent)

                Text(label)
                    .zappFont(.rowTitle, style: ZappColors.text)

                Spacer()
            }
            .padding(.horizontal, Constants.rowHorizontalPadding)
            .padding(.vertical, Constants.rowVerticalPadding)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : Constants.disabledOpacity)
        }
        .buttonStyle(.zappPress)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}

/// Page two: gallery / file / camera.
struct ChatMediaAttachmentSheet: View {
    private enum Constants {
        static let iconSize: CGFloat = 28
        static let tileHeight: CGFloat = 80
        static let tileSpacing: CGFloat = 12
        static let height: CGFloat = 220
    }

    @Environment(\.colorScheme) private var colorScheme

    let onChooseMedia: () -> Void
    let onAttachFile: () -> Void
    let onTakePhoto: () -> Void

    static var detentHeight: CGFloat { Constants.height }

    var body: some View {
        // 16pt title-to-tiles gap, matching Android's `Spacer(height = 16.dp)`.
        VStack(alignment: .leading, spacing: Design.Spacing._xl) {
            Text(String(localizable: .chatRoomMediaTitle))
                .zappFont(.sectionTitle, style: ZappColors.text)

            HStack(spacing: Constants.tileSpacing) {
                tile(
                    icon: Asset.Assets.Icons.imageLibrary.image,
                    label: String(localizable: .chatRoomMediaMedia),
                    action: onChooseMedia
                )

                tile(
                    icon: Asset.Assets.Icons.file.image,
                    label: String(localizable: .chatRoomMediaFile),
                    action: onAttachFile
                )

                tile(
                    icon: nil,
                    label: String(localizable: .chatRoomMediaCamera),
                    action: onTakePhoto
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tile(icon: Image?, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Design.Spacing._xs) {
                if let icon {
                    icon
                        .zImage(width: Constants.iconSize, height: Constants.iconSize, style: ZappColors.accent)
                } else {
                    // Design-system gap: `Assets.xcassets/Icons` has no camera glyph (`scan` is the
                    // QR viewfinder and would misread here), so the camera tile falls back to a
                    // system symbol. Adding a `camera` asset is a deliberate design-system
                    // extension, not something to improvise — same call as the group avatar in
                    // `ChatConversationRow`.
                    Image(systemName: "camera.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: Constants.iconSize, height: Constants.iconSize)
                        .zForegroundColor(ZappColors.accent)
                }

                Text(label)
                    .zappFont(.chip, style: ZappColors.text)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Constants.tileHeight)
            .background(ZappColors.surfaceAlt.color(colorScheme))
            .contentShape(Rectangle())
        }
        .buttonStyle(.zappPress)
        .accessibilityLabel(label)
    }
}

#Preview {
    ChatAttachmentSheet(
        isGroup: false,
        onShareAddress: { },
        onSendZec: { },
        onSplitBill: { },
        onAttachMedia: { }
    )
}
