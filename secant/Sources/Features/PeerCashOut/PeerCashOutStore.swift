// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation

/// The Peer cash-out flow: the amount form, the attempt it starts, and the order that attempt opens.
///
/// A linear push rather than a navigation stack, because every screen here carries the Zapp bottom
/// action bar and its own back — a `NavigationStack` would put a second back at the top.
@Reducer
struct PeerCashOut {
    @ObservableState
    struct State: Equatable {
        enum Page: Equatable {
            case form
            case progress
            case order
        }

        var form: PeerCashOutForm.State
        var progress: PeerCashOutProgress.State?
        var order: PeerOrderDetail.State?

        /// Derived rather than stored: the child state is what says which screen exists, and a
        /// separate cursor would be a second source of truth for the same fact.
        var page: Page {
            if order != nil { return .order }
            if progress != nil { return .progress }
            return .form
        }

        init(destinationCode: String) {
            form = PeerCashOutForm.State(destinationCode: destinationCode)
        }
    }

    enum Action: Equatable {
        case form(PeerCashOutForm.Action)
        case progress(PeerCashOutProgress.Action)
        case order(PeerOrderDetail.Action)
        case delegate(Delegate)

        enum Delegate: Equatable {
            case close
            case topUp
        }
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.form, action: \.form) {
            PeerCashOutForm()
        }

        Reduce { state, action in
            switch action {
            case .form(.delegate(.close)):
                return .send(.delegate(.close))

            case .form(.delegate(.topUp)):
                return .send(.delegate(.topUp))

            case let .form(.delegate(.openAttempt(attemptID))):
                state.progress = PeerCashOutProgress.State(attemptID: attemptID)
                return .none

            case let .form(.delegate(.openOrder(depositID))),
                 let .progress(.delegate(.openOrder(depositID))):
                state.order = PeerOrderDetail.State(depositID: depositID)
                return .none

            // Closing a screen drops only that screen's state. The attempt behind it keeps running
            // on the app-lifetime runner, so re-entering re-attaches rather than restarting.
            case .order(.delegate(.close)):
                state.order = nil
                return .none

            case .progress(.delegate(.close)):
                state.progress = nil
                return .none

            case .form, .progress, .order, .delegate:
                return .none
            }
        }
        .ifLet(\.progress, action: \.progress) {
            PeerCashOutProgress()
        }
        .ifLet(\.order, action: \.order) {
            PeerOrderDetail()
        }
    }
}
