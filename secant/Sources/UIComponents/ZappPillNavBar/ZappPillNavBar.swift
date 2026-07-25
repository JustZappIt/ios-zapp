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
        // Unread count chip: sharp rectangle, min 16pt, nudged onto the icon's top-trailing corner.
        static let badgeMinSize: CGFloat = 16
        static let badgeHPadding: CGFloat = 4
        static let badgeVPadding: CGFloat = 1
        static let badgeOffsetX: CGFloat = 6
        static let badgeOffsetY: CGFloat = -6
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
            .background(Design.Surfaces.bgSecondary.color(colorScheme))
            .overlay(
                Rectangle()
                    .strokeBorder(Design.Surfaces.strokePrimary.color(colorScheme), lineWidth: 1)
            )
            .shadow(color: Design.Text.primary.color(colorScheme).opacity(0.12), radius: 4, y: 2)
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
                UISelectionFeedbackGenerator().selectionChanged()
                onTabSelected(tab)
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                icon(tab)
                    .zImage(
                        width: Constants.iconSize,
                        height: Constants.iconSize,
                        style: isSelected ? Design.Btns.Primary.fg : Design.Text.tertiary
                    )

                if tab == .chats && chatUnreadCount > 0 {
                    unreadBadge
                }
            }
            .animation(.easeInOut(duration: 0.2), value: chatUnreadCount)
            .frame(maxWidth: .infinity)
            .frame(height: Constants.cellHeight)
            .background(isSelected ? Design.Surfaces.brandPrimary.color(colorScheme) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private func icon(_ tab: ZappTabs.Tab) -> Image {
        switch tab {
        case .pay: return Asset.Assets.Icons.pay.image
        case .chats: return Asset.Assets.Icons.messageChat.image
        case .you: return Asset.Assets.Icons.user.image
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
