import ComposableArchitecture
import Foundation
import Testing
@testable import zodl_internal

@Suite struct IronwoodAnnouncementTests {
    private struct KeychainWriteFailure: Error { }

    @MainActor @Test func learnMoreTappedShowsBrowser() async {
        let store = TestStore(initialState: IronwoodAnnouncement.State()) { IronwoodAnnouncement() }
        await store.send(.learnMoreTapped) { $0.isInAppBrowserOn = true }
        await store.finish()
    }

    @MainActor @Test func guideTappedShowsBrowserWithoutAcknowledging() async {
        let calls = LockIsolated<[Bool]>([])
        let store = TestStore(initialState: IronwoodAnnouncement.State()) { IronwoodAnnouncement() } withDependencies: {
            $0.walletStorage.importIronwoodAnnouncementFlag = { flag in calls.withValue { $0.append(flag) } }
        }
        await store.send(.guideTapped) { $0.isInAppBrowserOn = true }
        #expect(calls.value.isEmpty)
        await store.finish()
    }

    @MainActor @Test func continuePersistsTrueExactlyOnce() async {
        let calls = LockIsolated<[Bool]>([])
        let store = TestStore(initialState: IronwoodAnnouncement.State()) { IronwoodAnnouncement() } withDependencies: {
            $0.walletStorage.importIronwoodAnnouncementFlag = { flag in calls.withValue { $0.append(flag) } }
        }
        await store.send(.continueTapped)
        #expect(calls.value == [true])
        await store.finish()
    }

    @MainActor @Test func continueSwallowsKeychainFailure() async {
        let store = TestStore(initialState: IronwoodAnnouncement.State()) { IronwoodAnnouncement() } withDependencies: {
            $0.walletStorage.importIronwoodAnnouncementFlag = { _ in throw KeychainWriteFailure() }
        }
        await store.send(.continueTapped)
        await store.finish()
    }
}
