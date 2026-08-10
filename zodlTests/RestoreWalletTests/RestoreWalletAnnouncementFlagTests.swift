import ComposableArchitecture
import Testing
@testable import zodl_internal

@Suite(.serialized) @MainActor struct RestoreWalletAnnouncementFlagTests {
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
            await clock.advance(by: .milliseconds(900))
            await waitUntil { !store.state.path.isEmpty }
            #expect(!store.state.path.isEmpty)
            #expect(calls.value.isEmpty)
        }
    }

    @Test func restoreNeverPreAcknowledgesAnnouncement() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = RestoreWalletCoordFlow.State()
            state.birthday = 1_000_000
            let calls = LockIsolated<[Bool]>([])
            let store = makeStore(state: state, calls: calls)
            store.send(.resolveRestore)
            #expect(!store.state.path.isEmpty)
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
            $0.walletStorage = .noOp
            $0.walletStorage.importIronwoodAnnouncementFlag = { flag in calls.withValue { $0.append(flag) } }
        }
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(1)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
