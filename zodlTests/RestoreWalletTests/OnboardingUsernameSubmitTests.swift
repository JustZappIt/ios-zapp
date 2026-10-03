//
//  OnboardingUsernameSubmitTests.swift
//  zodlTests
//
//  The onboarding username step must only advance on a valid name, and only once. The keyboard's
//  Done key sends `continueTapped` without the button's disabled state, so the coordinator is the
//  only gate: an invalid name used to push an endless derivation spinner, and Done followed by the
//  button pushed derivation (and app lock setup) twice.
//

import ComposableArchitecture
import Testing
@testable import zodl_internal

@Suite(.serialized) @MainActor struct OnboardingUsernameSubmitTests {
    @Test func doneOnTooShortNameDoesNotAdvance() {
        let (store, id) = makeStore(displayName: "ab")

        store.send(.path(.element(id: id, action: .chatUsername(.continueTapped))))

        #expect(store.state.path.count == 1)
        #expect(store.state.path.last?.is(\.chatUsername) == true)
    }

    @Test func doneOnEmptyNameDoesNotAdvance() {
        let (store, id) = makeStore(displayName: "")

        store.send(.path(.element(id: id, action: .chatUsername(.continueTapped))))

        #expect(store.state.path.count == 1)
    }

    @Test func validNameAdvancesToDerivation() {
        let (store, id) = makeStore(displayName: "alice")

        store.send(.path(.element(id: id, action: .chatUsername(.continueTapped))))

        #expect(store.state.path.count == 2)
        #expect(store.state.path.last?.is(\.identityDerivation) == true)
    }

    @Test func doneThenButtonAdvancesOnlyOnce() {
        let (store, id) = makeStore(displayName: "alice")

        store.send(.path(.element(id: id, action: .chatUsername(.continueTapped))))
        store.send(.path(.element(id: id, action: .chatUsername(.continueTapped))))

        #expect(store.state.path.count == 2)
        #expect(store.state.path.last?.is(\.identityDerivation) == true)
    }

    @Test func sanitizeCapsAtMaxLength() {
        let long = String(repeating: "a", count: UsernameRules.maxLength + 5)

        #expect(UsernameRules.sanitize(long).count == UsernameRules.maxLength)
        #expect(UsernameRules.isValid(UsernameRules.sanitize("Alice_Smith-2026!!extra_long_name")))
    }

    private func makeStore(displayName: String) -> (StoreOf<RestoreWalletCoordFlow>, StackElementID) {
        var entry = ChatUsernameEntry.State.initial
        entry.displayName = displayName

        var state = RestoreWalletCoordFlow.State()
        state.path.append(.chatUsername(entry))
        // StackState hands out sequential ids from 0 under the test dependency context.
        let id = state.path.ids.last ?? 0

        let store = Store(initialState: state) { RestoreWalletCoordFlow() }
        return (store, id)
    }
}
