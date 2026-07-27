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

    /// The Zapp brandmark is a full-colour mark (it carries its own accent field), so it is drawn
    /// untinted and edge-to-edge, exactly as Android's `ChatListView.SupportContactRow` draws
    /// `img_zapp_logo` at 44dp.
    private var avatar: some View {
        Asset.Assets.zappLogo.image
            .resizable()
            .frame(width: Constants.avatarSize, height: Constants.avatarSize)
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
