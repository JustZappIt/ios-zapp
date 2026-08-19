//
//  ChatProfileRoutingTests.swift
//  zodlTests
//
//  `Root.State.path` holds ONE destination at a time, so the profile → wallet-address → profile
//  round trip is not free: a generic "back clears the path" handler would skip the profile and
//  drop the user on the You tab. These exercise `coordinatorReduce()` directly — the cases below
//  only move state, they resolve no dependencies.
//

import ComposableArchitecture
import Foundation
import Testing
@testable import zodl_internal

/// Serialized: `Root.State.initial` touches process-global `@Shared(.inMemory(...))` keys.
@Suite(.serialized) struct ChatProfileRoutingTests {
    private func route(from path: Root.State.Path?, _ action: Root.Action) -> Root.State {
        var state = Root.State.initial
        state.path = path
        // `_reduce` rather than `reduce`: TCA deprecates direct invocation of the latter, and
        // these cases are pure state moves with no effect to run through a store.
        _ = Root().coordinatorReduce()._reduce(into: &state, action: action)

        return state
    }

    @Test func theYouTabProfileRowOpensTheProfile() {
        withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            #expect(route(from: nil, .zappTabs(.chatProfileTapped)).path == .chatProfile)
        }
    }

    @Test func theWalletAddressRowPushesTheAddressScreen() {
        withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let state = route(from: .chatProfile, .chatProfile(.walletAddressTapped))

            #expect(state.path == .chatWalletAddress)
        }
    }

    @Test func walletAddressBackReturnsToTheProfileNotTheTabs() {
        withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let state = route(from: .chatWalletAddress, .chatWalletAddress(.backTapped))

            #expect(state.path == .chatProfile)
        }
    }

    @Test func profileBackReturnsToTheTabs() {
        withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let state = route(from: .chatProfile, .chatProfile(.backToHomeTapped))

            #expect(state.path == nil)
        }
    }

    /// Nothing is broadcast from the address screen, so an automatic server switch may run under it.
    @Test func theWalletAddressScreenIsNotASensitiveFlow() {
        withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = Root.State.initial
            state.path = .chatWalletAddress

            #expect(!state.isSensitiveFlowActive)
        }
    }
}
