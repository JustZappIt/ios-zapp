//
//  ZappPillNavBar.swift
//  Zapp
//

import SwiftUI
import UIKit

struct ZappPillNavBar: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let widthRatio = 0.81
        static let cellHeight: CGFloat = 48
        static let iconSize: CGFloat = 20
        static let inset: CGFloat = 5
        static let cellSpacing: CGFloat = 4
        // Unread count chip: sharp rectangle, min 16pt, pinned inside the cell's top-trailing
        // corner as Android's `Alignment.TopEnd` + `offset(-6, 4)`.
        static let badgeMinSize: CGFloat = 16
        static let badgeHPadding: CGFloat = 4
        static let badgeVPadding: CGFloat = 1
        static let badgeOffsetX: CGFloat = -6
        static let badgeOffsetY: CGFloat = 4
        static let badgeCountCap = 99
    }

    // Mirrors Android's `chip` typography with the badge's fontSize 10 / Bold override.
    private static let badgeFont = ZappTextStyle(weight: .bold, size: 10, lineHeight: 14, tracking: 0.4)

    let selectedTab: ZappTabs.Tab
    let chatUnreadCount: Int
    let onTabSelected: (ZappTabs.Tab) -> Void

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: Constants.cellSpacing) {
                ForEach(ZappTabs.Tab.allCases) { tab in
                    cell(tab)
                }
            }
            .padding(Constants.inset)
            .background(ZappColors.navPill.color(colorScheme))
            .overlay(
                Rectangle()
                    .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
            )
            // Static, as Android's `shadow(4.dp)`: the pill floats whether or not content is under it.
            .zappElevation()
            .frame(width: proxy.size.width * Constants.widthRatio)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(height: Constants.cellHeight + Constants.inset * 2)
    }

    @ViewBuilder
    private func cell(_ tab: ZappTabs.Tab) -> some View {
        let isSelected = tab == selectedTab

        Button {
            if tab != selectedTab {
                // Match Android's SegmentTick on every tab change.
                ZappHaptics.selection()
                onTabSelected(tab)
            }
        } label: {
            icon(tab, selected: isSelected)
                .zImage(
                    width: Constants.iconSize,
                    height: Constants.iconSize,
                    style: isSelected ? ZappColors.onAccent : ZappColors.textMuted
                )
                .frame(maxWidth: .infinity)
                .frame(height: Constants.cellHeight)
                .background(isSelected ? ZappColors.accent.color(colorScheme) : .clear)
                .animation(ZappMotion.content, value: isSelected)
                .overlay(alignment: .topTrailing) {
                    if tab == .chats && chatUnreadCount > 0 {
                        unreadBadge
                    }
                }
                .animation(ZappMotion.state, value: chatUnreadCount)
                .contentShape(Rectangle())
        }
        // Android ripples the cell in `accent`, or `onAccent` over the selected fill; no scale.
        .buttonStyle(.zappHighlight(tint: isSelected ? .onAccent : .accent))
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var unreadBadge: some View {
        Text(badgeText)
            .zappFont(Self.badgeFont, style: ZappColors.onAccent)
            .padding(.horizontal, Constants.badgeHPadding)
            .padding(.vertical, Constants.badgeVPadding)
            .frame(minWidth: Constants.badgeMinSize, minHeight: Constants.badgeMinSize)
            .background(ZappColors.danger.color(colorScheme))
            .offset(x: Constants.badgeOffsetX, y: Constants.badgeOffsetY)
            .transition(.scale.combined(with: .opacity))
    }

    // `max(_, 1)` keeps "0" from flashing while the badge scales out on the last read.
    private var badgeText: String {
        chatUnreadCount > Constants.badgeCountCap
            ? String(localizable: .zappTabsUnreadBadgeCap)
            : String(max(chatUnreadCount, 1))
    }

    /// Mirrors Android's `iconFor(tab, selected)`, which swaps each tab's outlined
    /// glyph for its filled counterpart on selection rather than only re-tinting it.
    private func icon(_ tab: ZappTabs.Tab, selected: Bool) -> Image {
        switch tab {
        case .pay:
            return selected ? Asset.Assets.Icons.payFilled.image : Asset.Assets.Icons.pay.image
        case .chats:
            return selected ? Asset.Assets.Icons.messageChatFilled.image : Asset.Assets.Icons.messageChat.image
        case .you:
            return selected ? Asset.Assets.Icons.userFilled.image : Asset.Assets.Icons.user.image
        }
    }
}

#Preview {
    VStack {
        Spacer()
        ZappPillNavBar(selectedTab: .chats, chatUnreadCount: 3) { _ in }
    }
    .applyScreenBackground()
}
