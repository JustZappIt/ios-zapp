//
//  ReceiveExplainerTests.swift
//  zodlTests
//

import Foundation
import Testing
import ComposableArchitecture
@testable import zodl_internal

// Serialized: `Receive.State` carries `@Shared(.inMemory(...))` keys.
@Suite(.serialized) @MainActor struct ReceiveExplainerTests {
    /// The address explainer is driven by one toggling action: the view's info button opens it
    /// for the selected address type, and both the sheet button and a swipe-down send it again.
    @Test func infoTappedTogglesTheExplainerForTheTappedAddressType() {
        withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            // A plain Store: `Receive.State` is not Equatable, and the action is a synchronous toggle.
            let store = Store(initialState: Receive.State()) { Receive() }

            store.send(.infoTapped(false))
            #expect(store.isAddressExplainerPresented)
            #expect(!store.isExplainerForShielded)

            store.send(.infoTapped(false))
            #expect(!store.isAddressExplainerPresented)

            store.send(.infoTapped(true))
            #expect(store.isAddressExplainerPresented)
            #expect(store.isExplainerForShielded)
        }
    }
}
