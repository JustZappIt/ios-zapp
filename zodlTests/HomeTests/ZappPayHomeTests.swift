//
//  ZappPayHomeTests.swift
//  zodlTests
//
//  Pay-tab behaviour Home owns for the Zapp shell: the Android shield explainer
//  (`ShieldFundsFromMessageUseCase`) and the once-per-episode sync-error sheet
//  (`HomeVM.hasSyncErrorBeenShown`).
//

import Combine
import ComposableArchitecture
import Foundation
import Testing
@testable @preconcurrency import ZcashLightClientKit
@testable import zodl_internal

@Suite(.serialized) @MainActor struct ZappPayHomeTests {
    private static func syncState(_ status: SyncStatus) -> RedactableSynchronizerState {
        var state = SynchronizerState.zero
        state.syncStatus = status
        return state.redacted
    }

    private func makeStore(
        initialState: Home.State = .initial,
        shieldCalls: LockIsolated<Int> = LockIsolated(0)
    ) -> TestStore<Home.State, Home.Action> {
        let store = TestStore(initialState: initialState) {
            Home()
        } withDependencies: {
            $0.mainQueue = .immediate
            $0.migrationManager = .noOp
            $0.walletStorage = .noOp
            $0.shieldingProcessor = ShieldingProcessorClient(
                observe: { Empty().eraseToAnyPublisher() },
                shieldFunds: { shieldCalls.withValue { $0 += 1 } }
            )
        }
        store.exhaustivity = .off
        return store
    }

    // MARK: - Shield explainer

    @Test func shieldWithoutAcknowledgementShowsTheExplainerFirst() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let shieldCalls = LockIsolated(0)
            let store = makeStore(shieldCalls: shieldCalls)

            await store.send(.zappShieldTapped)

            #expect(store.state.isZappShieldInfoPresented)
            #expect(shieldCalls.value == 0)
        }
    }

    @Test func shieldAfterDoNotShowAgainShieldsImmediately() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = Home.State.initial
            state.smartBannerState.isShieldingAcknowledged = true
            let shieldCalls = LockIsolated(0)
            let store = makeStore(initialState: state, shieldCalls: shieldCalls)

            await store.send(.zappShieldTapped)
            await store.receive(\.zappShieldInfoConfirmed)

            #expect(store.state.isZappShieldInfoPresented == false)
            #expect(shieldCalls.value == 1)
        }
    }

    @Test func confirmingTheExplainerDismissesAndShields() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = Home.State.initial
            state.isZappShieldInfoPresented = true
            let shieldCalls = LockIsolated(0)
            let store = makeStore(initialState: state, shieldCalls: shieldCalls)

            await store.send(.zappShieldInfoConfirmed)

            #expect(store.state.isZappShieldInfoPresented == false)
            #expect(shieldCalls.value == 1)
        }
    }

    @Test func shieldingLeavesAMigrationBannerInPlace() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = Home.State.initial
            state.smartBannerState.isOpen = true
            state.smartBannerState.priorityContent = .priorityMigration
            let store = makeStore(initialState: state)

            await store.send(.zappShieldInfoConfirmed)

            #expect(store.state.smartBannerState.isOpen)
            #expect(store.state.smartBannerState.priorityContent == .priorityMigration)
        }
    }

    // MARK: - Sync-error sheet

    @Test func syncErrorRaisesTheSheetOncePerEpisode() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let store = makeStore()
            let error = Self.syncState(.error(ZcashError.compactBlockProcessorCritical))

            await store.send(.smartBanner(.synchronizerStateChanged(error)))
            #expect(store.state.isZappSyncErrorSheetPresented)

            // The user closes it; the SDK's retry loop bounces through syncing back into error.
            await store.send(.binding(.set(\.isZappSyncErrorSheetPresented, false)))
            await store.send(.smartBanner(.synchronizerStateChanged(Self.syncState(.syncing(0.1, false)))))
            await store.send(.smartBanner(.synchronizerStateChanged(error)))
            #expect(store.state.isZappSyncErrorSheetPresented == false)

            // A completed sync ends the episode; the next failure raises the sheet again.
            await store.send(.smartBanner(.synchronizerStateChanged(Self.syncState(.upToDate))))
            #expect(store.state.hasZappSyncErrorEpisodeBeenShown == false)
            await store.send(.smartBanner(.synchronizerStateChanged(error)))
            #expect(store.state.isZappSyncErrorSheetPresented)
        }
    }
}
