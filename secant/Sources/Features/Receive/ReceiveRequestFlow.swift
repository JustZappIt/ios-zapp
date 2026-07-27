//
//  ReceiveRequestFlow.swift
//  Zapp
//
//  The Request-ZEC sub-chain (amount keyboard -> memo -> shareable QR), lifted out of Receive's
//  own `NavigationStack` so it can RISE instead of sliding in from the trailing edge.
//
//  Why: Android routes `NavigationTargets.REQUEST` through `ScreenAnimation.sheetEnterTransition`
//  (`RootNavGraph.kt` — `slideIntoContainer(SlideDirection.Up)` in, `Down` out) while every other
//  push uses the horizontal `enterTransition`. Receive itself stays a push on both platforms, so
//  only this three-screen chain moves; Phase 10 already established that converting Receive would
//  be a regression and would cut its edge-swipe/parallax preferences at a presentation boundary.
//
//  The iOS equivalent of "a full-screen route that rises and drops back down" is
//  `fullScreenCover`, not `.sheet`: Android's is a full destination, not a bottom sheet, and the
//  amount keyboard needs the whole screen. Receive keeps its own `NavigationStack` untouched, so
//  its back-swipe system is unaffected — the cover is a separate presentation with its own stack,
//  and `zashiBack`'s `@Environment(\.dismiss)` lands on the cover at the chain's root and pops
//  within it everywhere else.
//
//  This is a Zapp-side file beside the upstream `Receive*` ones rather than an edit to
//  `RequestZecCoordFlow`, which hardcodes the shielded address; Receive has to be able to request
//  into whichever segment the user has selected.
//

import ComposableArchitecture
import SwiftUI

@Reducer
struct ReceiveRequestFlow {
    @Reducer
    enum Path {
        case requestZec(RequestZec)
        case requestZecSummary(RequestZec)
    }

    @ObservableState
    struct State: Equatable {
        var memo = ""
        var path = StackState<Path.State>()
        var requestZecState = RequestZec.State.initial
        var zecKeyboardState = ZecKeyboard.State.initial

        init(address: RedactableString, maxPrivacy: Bool) {
            requestZecState.address = address
            requestZecState.maxPrivacy = maxPrivacy
        }
    }

    enum Action {
        /// The chain asked to close itself (Cancel on the summary). Receive tears the cover down.
        case dismissRequested
        case path(StackActionOf<Path>)
        case zecKeyboard(ZecKeyboard.Action)
    }

    init() { }

    var body: some Reducer<State, Action> {
        Scope(state: \.zecKeyboardState, action: \.zecKeyboard) {
            ZecKeyboard()
        }

        Reduce { state, action in
            switch action {
            case .zecKeyboard(.nextTapped):
                state.requestZecState.memoState.text = state.memo
                state.requestZecState.requestedZec = state.zecKeyboardState.amount.roundToAvoidDustSpend()
                state.path.append(.requestZec(state.requestZecState))
                return .none

            case .path(.element(id: _, action: .requestZec(.requestTapped))):
                for element in state.path {
                    if case .requestZec(let requestZecState) = element {
                        state.requestZecState.memoState = requestZecState.memoState
                        break
                    }
                }
                state.path.append(.requestZecSummary(state.requestZecState))
                return .none

                // Cancel used to `path.removeAll()` back to the Receive screen; the chain is its
                // own presentation now, so the equivalent is closing it.
            case .path(.element(id: _, action: .requestZecSummary(.cancelRequestTapped))):
                return .send(.dismissRequested)

            default:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
    }
}

// Declared here, in the same file as the macro-generated `Path.State`, so Swift can still
// synthesise the memberwise comparison — `@Reducer enum Path` does not add it itself. Without it
// `State` cannot be `Equatable`, and without THAT the flow cannot be driven from a `TestStore`.
extension ReceiveRequestFlow.Path.State: Equatable { }

struct ReceiveRequestFlowView: View {
    @Perception.Bindable var store: StoreOf<ReceiveRequestFlow>
    let tokenName: String

    var body: some View {
        WithPerceptionTracking {
            NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
                ZecKeyboardView(
                    store: store.scope(state: \.zecKeyboardState, action: \.zecKeyboard),
                    tokenName: tokenName
                )
                .navigationBarHidden(true)
            } destination: { store in
                switch store.case {
                case let .requestZec(store):
                    RequestZecView(store: store, tokenName: tokenName)
                case let .requestZecSummary(store):
                    RequestZecSummaryView(store: store, tokenName: tokenName)
                }
            }
            .navigationBarHidden(true)
        }
    }
}
