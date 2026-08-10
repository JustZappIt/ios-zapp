//
//  SmartBannerIncompatibleServerTests.swift
//  zodlTests
//

import ComposableArchitecture
import Foundation
import Testing
@testable @preconcurrency import ZcashLightClientKit
@testable import zodl_internal

@Suite(.serialized) @MainActor struct SmartBannerIncompatibleServerTests {
    private static let incompatibleServerError = ZcashError.compactBlockProcessorWrongConsensusBranchId(
        ConsensusBranchID(1_412_952_880),
        ConsensusBranchID(933_566_043)
    )

    private static func syncState(_ status: SyncStatus) -> RedactableSynchronizerState {
        var state = SynchronizerState.zero
        state.syncStatus = status
        return state.redacted
    }

    private func makeStore() -> TestStore<SmartBanner.State, SmartBanner.Action> {
        let store = TestStore(initialState: SmartBanner.State()) {
            SmartBanner()
        } withDependencies: {
            $0.mainQueue = .immediate
            $0.zcashSDKEnvironment.serverConfig = {
                UserPreferencesStorage.ServerConfig(host: "outdated.example.com", port: 443, isCustom: false)
            }
            // SupportDataGenerator reads the Tor setup flag while preparing the report.
            $0.walletStorage = .noOp
        }
        store.exhaustivity = .off
        return store
    }

    @Test func serverValidationFailureFlagsTheErrorAsIncompatibleServer() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let store = makeStore()

            await store.send(.synchronizerStateChanged(Self.syncState(.error(Self.incompatibleServerError))))

            #expect(store.state.lastKnownErrorIsIncompatibleServer)
            #expect(store.state.lastKnownErrorMessage.contains("outdated.example.com:443"))
            #expect(store.state.lastKnownErrorMessage.contains("0x5437f330"))
            #expect(store.state.lastKnownErrorMessage.contains("0x37a5165b"))
        }
    }

    @Test func genericSyncErrorDoesNotFlagIncompatibleServer() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let store = makeStore()

            await store.send(.synchronizerStateChanged(Self.syncState(.error(ZcashError.compactBlockProcessorCritical))))

            #expect(store.state.lastKnownErrorIsIncompatibleServer == false)
        }
    }

    @Test func unpreparedStatusDoesNotFlagIncompatibleServer() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let store = makeStore()

            await store.send(.synchronizerStateChanged(Self.syncState(.error(Self.incompatibleServerError))))
            #expect(store.state.lastKnownErrorIsIncompatibleServer)

            await store.send(.synchronizerStateChanged(Self.syncState(.unprepared)))

            #expect(store.state.lastKnownErrorIsIncompatibleServer == false)
        }
    }

    /// `SyncStatus.==` considers all errors equal, so this also protects the separate rendered-error
    /// comparison that refreshes both the message and classification when one failure replaces another.
    @Test func laterGenericErrorClearsTheFlag() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let store = makeStore()

            await store.send(.synchronizerStateChanged(Self.syncState(.error(Self.incompatibleServerError))))
            #expect(store.state.lastKnownErrorIsIncompatibleServer)

            await store.send(.synchronizerStateChanged(Self.syncState(.error(ZcashError.compactBlockProcessorCritical))))
            #expect(store.state.lastKnownErrorIsIncompatibleServer == false)
        }
    }

    @Test func recoveryClearsTheIncompatibleServerFlag() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let store = makeStore()

            await store.send(.synchronizerStateChanged(Self.syncState(.error(Self.incompatibleServerError))))
            #expect(store.state.lastKnownErrorIsIncompatibleServer)

            await store.send(.synchronizerStateChanged(Self.syncState(.upToDate)))
            #expect(store.state.lastKnownErrorIsIncompatibleServer == false)
        }
    }

    @Test func recurringIncompatibleServerErrorRearmsTheFlag() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let store = makeStore()

            await store.send(.synchronizerStateChanged(Self.syncState(.error(Self.incompatibleServerError))))
            #expect(store.state.lastKnownErrorIsIncompatibleServer)

            await store.send(.synchronizerStateChanged(Self.syncState(.upToDate)))
            #expect(store.state.lastKnownErrorIsIncompatibleServer == false)

            await store.send(.synchronizerStateChanged(Self.syncState(.error(Self.incompatibleServerError))))
            #expect(store.state.lastKnownErrorIsIncompatibleServer)
        }
    }

    @Test func supportReportCarriesTheServerAndBranchIds() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let store = makeStore()

            await store.send(.synchronizerStateChanged(Self.syncState(.error(Self.incompatibleServerError))))
            await store.send(.reportPrepared)

            let reportBody = store.state.supportData?.message ?? store.state.messageToBeShared ?? ""
            #expect(reportBody.contains("Server: outdated.example.com:443"))
            #expect(reportBody.contains("Expected branch ID: 0x5437f330"))
            #expect(reportBody.contains("Server's branch ID: 0x37a5165b"))
            #expect(reportBody.contains("Error code: ZCBPEO0011"))
        }
    }

    @Test func serverSwitchRequestDismissesEitherSheet() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let store = makeStore()

            await store.send(.smartBannerContentTapped)
            #expect(store.state.isSmartBannerSheetPresented)

            await store.send(.serverSwitchRequested)
            #expect(store.state.isSmartBannerSheetPresented == false)
            #expect(store.state.isSyncTimedOutSheetPresented == false)
        }
    }

    @Test func liveZappSheetOffersOnlyTheActionThatCanRecover() {
        #expect(ZappSyncErrorSheet.primaryRemedy(isIncompatibleServer: true) == .switchServer)
        #expect(ZappSyncErrorSheet.primaryRemedy(isIncompatibleServer: false) == .retry)
    }
}
