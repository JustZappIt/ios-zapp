//
//  ZappPillNavBar.swift
//  Zapp
//

import SwiftUI

struct ZappPillNavBar: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let widthRatio = 0.81
        static let cellHeight: CGFloat = 48
        static let iconSize: CGFloat = 20
        static let inset: CGFloat = 5
        static let cellSpacing: CGFloat = 4
        static let badgeSize: CGFloat = 8
    }

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
                    Circle()
                        .fill(Design.Utility.ErrorRed._500.color(colorScheme))
                        .frame(width: Constants.badgeSize, height: Constants.badgeSize)
                        .offset(x: 6, y: -4)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Constants.cellHeight)
            .background(isSelected ? Design.Surfaces.brandPrimary.color(colorScheme) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
