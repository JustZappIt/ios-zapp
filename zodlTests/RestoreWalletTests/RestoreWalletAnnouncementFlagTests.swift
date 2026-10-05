import ComposableArchitecture
import Testing
@testable import zodl_internal

@Suite(.serialized, .timeLimit(.minutes(1))) @MainActor struct RestoreWalletAnnouncementFlagTests {
    @Test func createNeverPreAcknowledgesAnnouncement() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let calls = LockIsolated<[Bool]>([])
            let clock = TestClock()
            let store = makeStore(
                state: RestoreWalletCoordFlow.State(),
                calls: calls,
                clock: clock
            )
            store.send(.createNewWalletRequested)
            // The effect may not have reached its 900ms pause when the test first advances, so
            // keep advancing until the step lands instead of advancing once and hoping.
            while store.state.path.isEmpty {
                await clock.advance(by: .milliseconds(900))
                try? await Task.sleep(for: .milliseconds(10))
            }
            #expect(!store.state.path.isEmpty)
            #expect(calls.value.isEmpty)
        }
    }

    @Test func restoreNeverPreAcknowledgesAnnouncement() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = RestoreWalletCoordFlow.State()
            state.path.append(.restoreSeedEntry(.initial))
            state.path.append(.restoreBirthday(.initial))
            let birthdayId = state.path.ids.last ?? 0
            let calls = LockIsolated<[Bool]>([])
            let store = makeStore(state: state, calls: calls)
            store.send(.path(.element(id: birthdayId, action: .restoreBirthday(.restoreRequested(1_000_000)))))
            await waitUntil { store.state.path.last?.is(\.seedBackup) == true }
            #expect(store.state.path.last?.is(\.seedBackup) == true)
            #expect(calls.value.isEmpty)
        }
    }

    private func makeStore(
        state: RestoreWalletCoordFlow.State,
        calls: LockIsolated<[Bool]>,
        clock: any Clock<Duration> = ImmediateClock()
    ) -> StoreOf<RestoreWalletCoordFlow> {
        Store(initialState: state) { RestoreWalletCoordFlow() } withDependencies: {
            $0.mnemonic = .noOp
            $0.continuousClock = clock
            $0.sdkSynchronizer = .noOp
            $0.userDefaults = .noOp
            $0.walletStorage = .noOp
            $0.walletStorage.importIronwoodAnnouncementFlag = { flag in calls.withValue { $0.append(flag) } }
        }
    }

    /// Polls until the effect chain lands. No deadline: a slow CI runner gets there later, not
    /// differently, and the suite's `.timeLimit` is the only clock.
    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        while !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
