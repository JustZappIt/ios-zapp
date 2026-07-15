//
//  ZappTabsStore.swift
//  Zapp
//

import ComposableArchitecture
import Foundation

@Reducer
struct ZappTabs {
    enum Tab: Int, Equatable, CaseIterable, Identifiable {
        case pay
        case chats
        case you

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .pay: return String(localizable: .zappTabsPay)
            case .chats: return String(localizable: .zappTabsChats)
            case .you: return String(localizable: .zappTabsYou)
            }
        }
    }

    @ObservableState
    struct State: Equatable {
        var selectedTab: Tab = .chats
        var chatUnreadCount = 0

        /// Fed from Root's ZappMessagingState. The Chats tab shows the identity
        /// setup screen until this is true.
        var hasChatIdentity = false

        /// The chat identity's display name, for the You tab's profile card.
        var displayName: String?

        // Set by tab content when it pushes a fullscreen sub-screen that owns its
        // own bottom CTA, so the two don't overlap.
        var hideNavPill = false
    }

    enum Action: Equatable {
        case tabSelected(Tab)
        case fullscreenChanged(Bool)

        // Routed by RootCoordinator into Root's path overlays, the same way Home's
        // *Tapped actions are. The You tab stays navigation-agnostic.
        case allSettingsTapped
        case chatContactsTapped
        case chatProfileTapped
        case chooseServerTapped
        case localCurrencyTapped
        case onlineStatusTapped
        case p2pPaymentMethodTapped
        case p2pTransactionsTapped
        case readReceiptsTapped
        case torTapped
    }

    init() { }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .tabSelected(let tab):
                state.selectedTab = tab
                return .none

            case .fullscreenChanged(let isFullscreen):
                state.hideNavPill = isFullscreen
                return .none

            case .allSettingsTapped, .chatContactsTapped, .chatProfileTapped, .chooseServerTapped,
            .localCurrencyTapped, .onlineStatusTapped, .p2pPaymentMethodTapped, .p2pTransactionsTapped,
            .readReceiptsTapped, .torTapped:
                return .none
            }
        }
    }
}

// MARK: Placeholders

extension ZappTabs.State {
    static var initial: ZappTabs.State {
        .init()
    }
}

extension ZappTabs {
    @MainActor
    static let initial = StoreOf<ZappTabs>(
        initialState: .initial
    ) {
        ZappTabs()
    }
}
