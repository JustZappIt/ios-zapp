@preconcurrency import Combine
import ComposableArchitecture
import Foundation
import Testing
@testable @preconcurrency import ZcashLightClientKit
@testable import zodl_internal

// Root.State's test-only Equatable conformance lives in
// RootInitializeSDKSingleFlightTests.swift, so these tests use a plain Store.
@Suite(.serialized) @MainActor struct RootIronwoodAnnouncementGateTests {
    private let activation: BlockHeight = 1_000_000

    private func state() -> Root.State {
        var state = Root.State.initial
        state.destinationState.destination = .home
        state.splashAppeared = true
        return state
    }

    private func syncState(_ tip: BlockHeight) -> RedactableSynchronizerState {
        var state = SynchronizerState.zero
        state.syncStatus = .upToDate
        state.latestBlockHeight = tip
        return state.redacted
    }

    private func store(
        _ state: Root.State? = nil,
        flag: Bool? = nil,
        reads: LockIsolated<Int>? = nil
    ) -> StoreOf<Root> {
        Store(initialState: state ?? self.state()) { Root() } withDependencies: {
            $0.mainQueue = .immediate
            $0.zcashSDKEnvironment.ironwoodActivationHeight = { activation }
            $0.walletStorage = .noOp
            $0.walletStorage.exportIronwoodAnnouncementFlag = {
                reads?.withValue { $0 += 1 }
                return flag
            }
        }
    }

    @Test func knownTipMustReachActivationBeforeReadingKeychain() async {
        await withDependencies { $0.defaultInMemoryStorage = InMemoryStorage() } operation: {
            let reads = LockIsolated(0)
            let store = store(flag: nil, reads: reads)
            store.send(.synchronizerStateChanged(syncState(0)))
            store.send(.synchronizerStateChanged(syncState(activation - 1)))
            #expect(reads.value == 0)
            #expect(store.state.destinationState.destination == .home)
            store.send(.synchronizerStateChanged(syncState(activation)))
            #expect(reads.value == 1)
            #expect(store.state.destinationState.destination == .ironwoodAnnouncement)
        }
    }

    @Test func acknowledgedTrueReadsOnceAndResolvesSession() async {
        await withDependencies { $0.defaultInMemoryStorage = InMemoryStorage() } operation: {
            let reads = LockIsolated(0)
            let store = store(flag: true, reads: reads)
            store.send(.synchronizerStateChanged(syncState(activation)))
            store.send(.synchronizerStateChanged(syncState(activation + 1)))
            store.send(.synchronizerStateChanged(syncState(activation + 2)))
            #expect(reads.value == 1)
            #expect(store.state.ironwoodAnnouncementResolved)
            #expect(store.state.destinationState.destination == .home)
        }
    }

    @Test func falseIsNotAcknowledgementAndPresentationOccursOnce() async {
        await withDependencies { $0.defaultInMemoryStorage = InMemoryStorage() } operation: {
            let store = store(flag: false)
            store.send(.synchronizerStateChanged(syncState(activation)))
            #expect(store.state.destinationState.destination == .ironwoodAnnouncement)
            #expect(store.state.destinationState.previousDestination == .home)
            store.send(.synchronizerStateChanged(syncState(activation + 1)))
            #expect(store.state.destinationState.previousDestination == .home)
        }
    }

    @Test func gateRunsBeforeMissingSelectedAccountReturn() async {
        await withDependencies { $0.defaultInMemoryStorage = InMemoryStorage() } operation: {
            var initial = state()
            initial.$selectedWalletAccount.withLock { $0 = nil }
            let store = store(initial)
            store.send(.synchronizerStateChanged(syncState(activation)))
            #expect(store.state.destinationState.destination == .ironwoodAnnouncement)
        }
    }

    @Test func representativeActiveRootPathsBlockPresentation() async {
        await withDependencies { $0.defaultInMemoryStorage = InMemoryStorage() } operation: {
            for path: Root.State.Path in [.receive, .sendCoordFlow, .offramp, .chatRoom, .settings, .supportChat] {
                var initial = state()
                initial.path = path
                let store = store(initial)
                store.send(.synchronizerStateChanged(syncState(activation)))
                #expect(store.state.destinationState.destination == .home)
                #expect(!store.state.ironwoodAnnouncementResolved)
            }
        }
    }

    @Test func everyNonPathSafetyTermBlocksPresentation() async {
        await withDependencies { $0.defaultInMemoryStorage = InMemoryStorage() } operation: {
            var notHome = state()
            notHome.destinationState.destination = .onboarding
            var signing = state()
            signing.signWithKeystoneCoordFlowBinding = true
            var server = state()
            server.serverSetupViewBinding = true
            var alert = state()
            alert.alert = AlertState.cantLoadSeedPhrase()
            var poolSheet = state()
            poolSheet.homeState.isZappPoolBalancesSheetPresented = true
            var syncSheet = state()
            syncSheet.homeState.isZappSyncErrorSheetPresented = true
            var splash = state()
            splash.splashAppeared = false

            for initial in [notHome, signing, server, alert, poolSheet, syncSheet, splash] {
                let store = store(initial)
                store.send(.synchronizerStateChanged(syncState(activation)))
                #expect(store.state.destinationState.destination != .ironwoodAnnouncement)
                #expect(!store.state.ironwoodAnnouncementResolved)
            }
        }
    }

    @Test func dismissedZappSheetLetsTheBlockedAnnouncementRetry() async {
        await withDependencies { $0.defaultInMemoryStorage = InMemoryStorage() } operation: {
            var initial = state()
            initial.homeState.isZappPoolBalancesSheetPresented = true
            let store = store(initial)

            store.send(.synchronizerStateChanged(syncState(activation)))
            #expect(store.state.destinationState.destination == .home)
            #expect(!store.state.ironwoodAnnouncementResolved)

            store.send(.home(.binding(.set(\.isZappPoolBalancesSheetPresented, false))))
            store.send(.synchronizerStateChanged(syncState(activation + 1)))
            #expect(store.state.destinationState.destination == .ironwoodAnnouncement)
        }
    }

    @Test func blockedAttemptDoesNotConsumeLatchAndRetries() async {
        await withDependencies { $0.defaultInMemoryStorage = InMemoryStorage() } operation: {
            var initial = state()
            initial.path = .receive
            let store = store(initial)
            store.send(.synchronizerStateChanged(syncState(activation)))
            #expect(!store.state.ironwoodAnnouncementResolved)
            store.send(.receive(.backToHomeTapped))
            store.send(.synchronizerStateChanged(syncState(activation + 1)))
            #expect(store.state.destinationState.destination == .ironwoodAnnouncement)
        }
    }

    @Test func foregroundUsesRetainedTip() async {
        await withDependencies { $0.defaultInMemoryStorage = InMemoryStorage() } operation: {
            var initial = state()
            initial.$featureFlags.withLock { $0 = FeatureFlags(appLaunchBiometric: false) }
            let latest: SynchronizerState = {
                var value = SynchronizerState.zero
                value.syncStatus = .upToDate
                value.latestBlockHeight = activation
                return value
            }()
            let store = Store(initialState: initial) { Root() } withDependencies: {
                $0.mainQueue = .immediate
                $0.zcashSDKEnvironment.ironwoodActivationHeight = { activation }
                $0.walletStorage = .noOp
                $0.walletStorage.exportIronwoodAnnouncementFlag = { nil }
                $0.diskSpaceChecker.hasEnoughFreeSpaceForSync = { true }
                $0.sdkSynchronizer = .mocked(
                    stateStream: { Empty().eraseToAnyPublisher() },
                    latestState: { latest },
                    start: { _ in throw GateStubError() },
                    getAllTransactions: { _ in [] }
                )
            }
            store.send(.initialization(.appDelegate(.willEnterForeground)))
            #expect(store.state.destinationState.destination == .ironwoodAnnouncement)
        }
    }

    @Test func continueReturnsHomeAndDeliversDeferredHealNotice() async {
        await withDependencies { $0.defaultInMemoryStorage = InMemoryStorage() } operation: {
            var initial = state()
            initial.isStaleWalletHealedAlertPending = true
            let store = store(initial)
            store.send(.synchronizerStateChanged(syncState(activation)))
            #expect(store.state.alert == nil)
            store.send(.ironwoodAnnouncement(.continueTapped))
            #expect(store.state.destinationState.destination == .home)
            await waitUntil { store.state.alert != nil }
            #expect(store.state.alert?.title == AlertState.staleWalletDatabaseHealed().title)
            #expect(!store.state.isStaleWalletHealedAlertPending)
        }
    }

    @Test func debugResetClearsSessionLatch() async throws {
        try await withDependencies { $0.defaultInMemoryStorage = InMemoryStorage() } operation: {
            var initial = state()
            initial.ironwoodAnnouncementResolved = true
            initial.settingsState.path.append(.advancedSettings(.initial))
            let store = store(initial, flag: false)
            let id = try #require(store.state.settingsState.path.ids.first)
            store.send(.settings(.path(.element(
                id: id,
                action: .advancedSettings(.debugResetIronwoodAnnouncementTapped)
            ))))
            #expect(!store.state.ironwoodAnnouncementResolved)
            store.send(.synchronizerStateChanged(syncState(activation)))
            #expect(store.state.destinationState.destination == .ironwoodAnnouncement)
        }
    }
}

private struct GateStubError: Error { }

@MainActor private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + 5_000_000_000
    while !condition(), DispatchTime.now().uptimeNanoseconds < deadline {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(condition(), "Timed out waiting for Root state")
}
