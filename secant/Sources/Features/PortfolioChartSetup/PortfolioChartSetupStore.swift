// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture

@Reducer
struct PortfolioChartSetup {
    @ObservableState
    struct State: Equatable {
        var isEnabled = true
        var savedIsEnabled = true

        var isSaveButtonDisabled: Bool {
            isEnabled == savedIsEnabled
        }
    }

    enum Action: Equatable {
        case backToHomeTapped
        case enabledToggled
        case onAppear
        case saveChangesTapped
    }

    @Dependency(\.userStoredPreferences)
    var userStoredPreferences

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                let enabled = userStoredPreferences.portfolioChartEnabled()
                state.isEnabled = enabled
                state.savedIsEnabled = enabled
                return .none

            case .enabledToggled:
                state.isEnabled.toggle()
                return .none

            case .saveChangesTapped:
                userStoredPreferences.setPortfolioChartEnabled(state.isEnabled)
                state.savedIsEnabled = state.isEnabled
                return .send(.backToHomeTapped)

            case .backToHomeTapped:
                return .none
            }
        }
    }
}

extension PortfolioChartSetup.State {
    static var initial: Self { .init() }
}
