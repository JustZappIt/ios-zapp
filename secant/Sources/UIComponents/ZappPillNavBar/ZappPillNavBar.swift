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
        // Shadow at rest and at full elevation. The pill floats over the content even when
        // nothing is scrolled under it, so it keeps a hairline of separation at rest and only
        // deepens once content is actually passing beneath (Appendix C.5).
        static let shadowRestOpacity: CGFloat = 0.04
        static let shadowLiftOpacity: CGFloat = 0.10
        static let shadowRestRadius: CGFloat = 2
        static let shadowLiftRadius: CGFloat = 3
        static let shadowRestOffsetY: CGFloat = 1
        static let shadowLiftOffsetY: CGFloat = 2
    }

    // Mirrors Android's `chip` typography with the badge's fontSize 10 / Bold override.
    private static let badgeFont = ZappTextStyle(weight: .bold, size: 10, lineHeight: 14, tracking: 0.4)

    let selectedTab: ZappTabs.Tab
    let chatUnreadCount: Int
    /// 0 when the tab beneath is at the top of its scroll, 1 once content is running under the
    /// pill. Anything in between is the ramp.
    var elevation: CGFloat = 0
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
            .shadow(
                color: Design.Text.primary.color(colorScheme).opacity(shadowOpacity),
                radius: Constants.shadowRestRadius + Constants.shadowLiftRadius * liftProgress,
                y: Constants.shadowRestOffsetY + Constants.shadowLiftOffsetY * liftProgress
            )
            .frame(width: proxy.size.width * Constants.widthRatio)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(height: Constants.cellHeight + Constants.inset * 2)
    }

    private var liftProgress: CGFloat {
        min(1, max(0, elevation))
    }

    private var shadowOpacity: CGFloat {
        Constants.shadowRestOpacity + Constants.shadowLiftOpacity * liftProgress
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
            ZStack(alignment: .topTrailing) {
                icon(tab, selected: isSelected)
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
