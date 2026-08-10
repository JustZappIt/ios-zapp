import ComposableArchitecture
import Testing
@testable import zodl_internal

@Suite(.serialized) struct AdvancedSettingsDebugResetTests {
    @MainActor @Test func debugResetWritesFalseExactlyOnceWithoutAuthentication() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let calls = LockIsolated<[Bool]>([])
            let store = TestStore(initialState: AdvancedSettings.State()) { AdvancedSettings() } withDependencies: {
                $0.walletStorage.importIronwoodAnnouncementFlag = { flag in calls.withValue { $0.append(flag) } }
            }
            await store.send(.debugResetIronwoodAnnouncementTapped)
            #expect(calls.value == [false])
            await store.finish()
        }
    }
}
