//
//  ZappTabsView.swift
//  Zapp
//
//  Zapp fork: iOS analog of android-zapp's `ZappTabsScaffold` +
//  `FloatingPillNavBar`. The persistent bottom-tab shell that replaces
//  upstream's Home-rooted NavigationStack as the app's `.home` surface.
//
//  Tab set mirrors Android (Pay / Chats / You) minus the messaging tabs:
//  Chats and Contacts arrive with the messaging phase - `ZappTab` and the
//  pill below are built so those cases slot in without restructuring
//  (see docs/zapp-phase2-shell.md, "Chats/Contacts seam").
//

import SwiftUI
import UIKit
import ComposableArchitecture

/// Android `ZappTab`. Phase 2 ships PAY and YOU; CHATS lands with messaging.
enum ZappTab: CaseIterable, Equatable {
    case pay
    case you

    var title: String {
        switch self {
        case .pay: return String(localizable: .zappTabPay)
        case .you: return String(localizable: .zappTabYou)
        }
    }

    var icon: Image {
        switch self {
        case .pay: return Asset.Assets.Icons.pay.image
        case .you: return Asset.Assets.Icons.user.image
        }
    }
}

struct ZappTabsView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<Root>
    let tokenName: String

    // Android holds the current tab in `rememberSaveable` view state; iOS
    // equivalent is view-local @State. Deep flows never depend on it.
    @State private var selectedTab: ZappTab = .pay

    var body: some View {
        WithPerceptionTracking {
            ZStack(alignment: .bottom) {
                ZappColor.bg(colorScheme)
                    .ignoresSafeArea()

                switch selectedTab {
                case .pay:
                    WalletTabView(store: store, tokenName: tokenName)
                        .transition(.opacity)
                case .you:
                    YouTabView(
                        store: store.scope(state: \.settingsState, action: \.settings)
                    )
                    .transition(.opacity)
                }

                // The You tab's pushed sub-screens own the full height (and any
                // bottom dock), so the pill hides while its stack is non-empty -
                // same behavior as Android where You rows navigate out of the
                // tabs scaffold.
                if store.settingsState.path.isEmpty || selectedTab == .pay {
                    FloatingPillNavBar(
                        selectedTab: selectedTab,
                        onSelect: { tab in
                            if tab != selectedTab {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                            withAnimation(.easeInOut(duration: ZappMotion.content)) {
                                selectedTab = tab
                            }
                        }
                    )
                }
            }
            .animation(.easeInOut(duration: ZappMotion.content), value: selectedTab)
        }
    }
}

/// Android `FloatingPillNavBar`: floating sharp-cornered pill, equal-width
/// icon cells, accent-filled selected cell. Unread badge slot arrives with
/// the Chats tab.
struct FloatingPillNavBar: View {
    @Environment(\.colorScheme) private var colorScheme

    let selectedTab: ZappTab
    let onSelect: (ZappTab) -> Void

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 4) {
                ForEach(ZappTab.allCases, id: \.self) { tab in
                    let isSelected = tab == selectedTab

                    Button {
                        onSelect(tab)
                    } label: {
                        tab.icon
                            .zImage(
                                size: 20,
                                color: isSelected
                                ? ZappColor.onAccent(colorScheme)
                                : ZappColor.textMuted(colorScheme)
                            )
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(isSelected ? ZappColor.accent(colorScheme) : Color.clear)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
            .padding(5)
            .background(ZappColor.navPill(colorScheme))
            .overlay {
                Rectangle()
                    .stroke(ZappColor.border(colorScheme), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
            .frame(width: proxy.size.width * 0.81)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 58 + 12)
        .padding(.bottom, 12)
    }
}
