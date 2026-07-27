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

/// The padding the presenting view puts around either page, plus room for the drag indicator and
/// a little slack for larger Dynamic Type. Both pages' detents are quoted inclusive of it, so the
/// sheet stops exactly at its content instead of leaving a band of empty surface underneath.
enum ChatAttachmentSheetChrome {
    static let top = Design.Spacing._xl
    static let bottom = Design.Spacing._3xl
    static let dragIndicator: CGFloat = 12
    static let slack: CGFloat = 12

    static var total: CGFloat { top + bottom + dragIndicator + slack }
}

/// Page one: share address / send ZEC / split bill / attach media.
struct ChatAttachmentSheet: View {
    private enum Constants {
        static let iconSize: CGFloat = 24
        static let rowVerticalPadding: CGFloat = 16
        static let rowHorizontalPadding: CGFloat = 16
        static let dividerInset: CGFloat = 8
        static let disabledOpacity: CGFloat = 0.4
        static let rowCount: CGFloat = 4
    }

    @Environment(\.colorScheme) private var colorScheme

    let isGroup: Bool
    let onShareAddress: () -> Void
    let onSendZec: () -> Void
    let onSplitBill: () -> Void
    let onAttachMedia: () -> Void

    /// Derived from this sheet's own layout rather than eyeballed, so the detent keeps matching
    /// the content if a padding changes: four rows, the hairlines between them, and the chrome
    /// the presenting view wraps it in.
    static var detentHeight: CGFloat {
        let rowHeight = Constants.iconSize + Constants.rowVerticalPadding * 2

        return (rowHeight * Constants.rowCount) + (Constants.rowCount - 1) + ChatAttachmentSheetChrome.total
    }

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
        static let titleHeight: CGFloat = 24
    }

    @Environment(\.colorScheme) private var colorScheme

    let onChooseMedia: () -> Void
    let onAttachFile: () -> Void
    let onTakePhoto: () -> Void

    /// Title, the 16pt gap under it, one row of tiles, and the shared chrome.
    static var detentHeight: CGFloat {
        Constants.titleHeight + Design.Spacing._xl + Constants.tileHeight + ChatAttachmentSheetChrome.total
    }

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
                    icon: Asset.Assets.Icons.camera.image,
                    label: String(localizable: .chatRoomMediaCamera),
                    action: onTakePhoto
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tile(icon: Image, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Design.Spacing._xs) {
                icon
                    .zImage(width: Constants.iconSize, height: Constants.iconSize, style: ZappColors.accent)

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
