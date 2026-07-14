//
//  ZappTabsView.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI

struct ZappTabsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Perception.Bindable var store: StoreOf<ZappTabs>

    let homeStore: StoreOf<Home>
    let tokenName: String

    var body: some View {
        WithPerceptionTracking {
            ZStack(alignment: .bottom) {
                // Fade-through, not a slide: tab switches are lateral moves, not navigation.
                content()
                    .id(store.selectedTab)
                    .transition(.opacity)

                if !store.hideNavPill {
                    ZappPillNavBar(
                        selectedTab: store.selectedTab,
                        chatUnreadCount: store.chatUnreadCount
                    ) { tab in
                        store.send(.tabSelected(tab), animation: .easeInOut(duration: 0.2))
                    }
                    .padding(.horizontal, Design.Spacing._lg)
                    .padding(.bottom, Design.Spacing._md)
                    .transition(.opacity)
                }
            }
        }
    }

    @ViewBuilder
    private func content() -> some View {
        switch store.selectedTab {
        case .pay:
            HomeView(store: homeStore, tokenName: tokenName)
        case .chats:
            placeholder(.chats)
        case .you:
            SettingsTabContent(store: store)
        }
    }

    private func placeholder(_ tab: ZappTabs.Tab) -> some View {
        VStack {
            Spacer()
            Text(tab.title)
                .zFont(.semiBold, size: 24, style: Design.Text.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .applyScreenBackground()
    }
}
