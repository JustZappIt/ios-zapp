//
//  SupportContactRow.swift
//  Zapp
//
//  The aggregate "Zapp Support" row pinned above the conversation list, mirroring
//  `ChatListView.kt: SupportContactRow`.
//

import SwiftUI

struct SupportContactRow: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let avatarSize: CGFloat = 44
        static let avatarIconSize: CGFloat = 22
        static let horizontalPadding: CGFloat = 14
        static let verticalPadding: CGFloat = 12
        static let spacing: CGFloat = 12
    }

    let subtitle: String
    var unreadCount = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) { row }
            .buttonStyle(.zappPress)
    }

    private var row: some View {
        HStack(spacing: Constants.spacing) {
            avatar

            VStack(alignment: .leading, spacing: Design.Spacing._xxs) {
                Text(String(localizable: .supportChatTitle))
                    .zappFont(.rowTitle, style: ZappColors.text)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(subtitle)
                    .zappFont(.rowSubtitle, style: ZappColors.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if unreadCount > 0 {
                Text("\(unreadCount)")
                    .zappFont(.chip, style: ZappColors.onAccent)
                    .padding(.horizontal, Design.Spacing._sm)
                    .padding(.vertical, Design.Spacing._xxs)
                    .background(ZappColors.accent.color(colorScheme))
            }
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.vertical, Constants.verticalPadding)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    /// Design-system gap: Android draws this row with its `img_zapp_logo` brandmark, and the iOS
    /// catalogue ships no Zapp logo asset (only the Zashi/ZODL brandmarks, which would be the
    /// wrong mark here). The row keeps the list's own accent-square avatar with the help glyph
    /// until a Zapp brandmark is added to `Assets.xcassets` — a deliberate design-system
    /// extension rather than something to improvise.
    private var avatar: some View {
        Asset.Assets.Icons.help.image
            .zImage(
                width: Constants.avatarIconSize,
                height: Constants.avatarIconSize,
                style: ZappColors.onAccent
            )
            .frame(width: Constants.avatarSize, height: Constants.avatarSize)
            .background(ZappColors.accent.color(colorScheme))
    }
}

#Preview {
    VStack(spacing: 0) {
        SupportContactRow(subtitle: "Report issues, share feedback") { }

        ZappRowDivider(inset: true)

        SupportContactRow(subtitle: "How can we help?", unreadCount: 2) { }
    }
    .applyScreenBackground()
}
