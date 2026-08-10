//
//  IronwoodAnnouncementStore.swift
//  Zapp
//

import ComposableArchitecture

@Reducer
struct IronwoodAnnouncement {
    @ObservableState
    struct State: Equatable {
        var isInAppBrowserOn = false
    }

    enum Action: BindableAction, Equatable {
        case binding(BindingAction<IronwoodAnnouncement.State>)
        case learnMoreTapped
        case guideTapped
        case continueTapped
    }

    @Dependency(\.walletStorage) var walletStorage

    init() { }

    var body: some Reducer<State, Action> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .learnMoreTapped:
                state.isInAppBrowserOn = true
                return .none

            case .guideTapped:
                // Opening either link is deliberately not acknowledgement;
                // only Continue persists the one-time flag.
                state.isInAppBrowserOn = true
                return .none

            case .continueTapped:
                // Root observes this action and owns the transition to Home.
                // A failed keychain write must not trap the user on this screen.
                try? walletStorage.importIronwoodAnnouncementFlag(true)
                return .none
            }
        }
    }
}
