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
    let chatsListStore: StoreOf<ChatsList>
    let chatIdentitySetupStore: StoreOf<ChatIdentitySetup>
    let chatProfileStore: StoreOf<ChatProfile>
    let tokenName: String

    /// How far the visible tab's list has scrolled, published by `zappScrollShadowSource()`.
    @State private var scrollProgress: CGFloat = 0

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
                        chatUnreadCount: store.chatUnreadCount,
                        elevation: scrollProgress / ZappScrollEdge.shadowRampDistance
                    ) { tab in
                        store.send(.tabSelected(tab), animation: .easeInOut(duration: 0.2))
                    }
                    .padding(.horizontal, Design.Spacing._lg)
                    .padding(.bottom, Design.Spacing._md)
                    .transition(.opacity)
                }
            }
            .onPreferenceChange(ZappScrollProgressKey.self) { scrollProgress = $0 }
        }
    }

    @ViewBuilder
    private func content() -> some View {
        switch store.selectedTab {
        case .pay:
            ZappPayView(store: homeStore, tokenName: tokenName)
        case .chats:
            if store.hasChatIdentity {
                ChatsListView(store: chatsListStore)
            } else {
                ChatIdentitySetupView(store: chatIdentitySetupStore)
            }
        case .you:
            SettingsTabContent(
                store: store,
                chatProfileStore: chatProfileStore,
                displayName: store.displayName
            )
        }
    }
}
