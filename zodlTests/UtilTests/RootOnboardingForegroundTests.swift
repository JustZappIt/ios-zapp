//
//  RootOnboardingForegroundTests.swift
//  zodlTests
//
//  A foreground while onboarding is on screen must not re-run the launch chain. Onboarding saves
//  a new wallet before seed backup but prepares it only after, so the re-run found keys without
//  database files, marked the wallet as restoring and routed home mid-flow, skipping the username
//  step — Chats then asked for it a second time.
//

@preconcurrency import Combine
import ComposableArchitecture
import Foundation
import Testing
@testable @preconcurrency import ZcashLightClientKit
@testable import zodl_internal

@Suite(.serialized) @MainActor struct RootOnboardingForegroundTests {
    private static let seedDerivedAccount = WalletAccount(
        Account(
            id: AccountUUID(id: [UInt8](repeating: 0x01, count: 16)),
            name: "Zashi",
            keySource: "zashi",
            seedFingerprint: [UInt8](repeating: 0x02, count: 32),
            hdAccountIndex: Zip32AccountIndex(0),
            ufvk: nil,
            uivk: nil
        )
    )

    private func makeStore(
        destination: Root.DestinationState.Destination,
        prepareCount: LockIsolated<Int>
    ) -> TestStore<Root.State, Root.Action> {
        let seedDerivedAccount = Self.seedDerivedAccount
        let initialState = Root.State(
            destinationState: Root.DestinationState(internalDestination: destination),
            exportLogsState: ExportLogs.State(),
            onboardingState: RestoreWalletCoordFlow.State(),
            phraseDisplayState: RecoveryPhraseDisplay.State(),
            walletConfig: .initial,
            welcomeState: Welcome.State()
        )
        let store = TestStore(initialState: initialState) {
            Root()
        } withDependencies: {
            $0.defaultInMemoryStorage = InMemoryStorage()
            $0.mainQueue = .immediate
            $0.exchangeRate = .noOp
            $0.autolockHandler = .noOp
            $0.shieldingProcessor = ShieldingProcessorClient(
                observe: { Empty().eraseToAnyPublisher() },
                shieldFunds: { }
            )
            $0.mnemonic = .noOp
            $0.diskSpaceChecker.hasEnoughFreeSpaceForSync = { true }
            // The window this covers: the wallet is in the keychain, its database is not yet.
            $0.databaseFiles = .noOp
            $0.databaseFiles.areDbFilesPresentFor = { _ in false }
            $0.walletStorage = .noOp
            $0.walletStorage.areKeysPresent = { true }
            $0.walletStorage.exportWallet = { .placeholder }
            $0.userDefaults.objectForKey = { _ in nil }
            $0.userDefaults.setValue = { _, _ in }
            $0.userDefaults.remove = { _ in }
            $0.readTransactionsStorage = .noOp
            $0.addressBook.allLocalContacts = { _ in (AddressBookContacts.empty, .notAttempted) }
            $0.userMetadataProvider.load = { _ in }
            // Foreground and launch both consult the migration lane; this suite is not about it.
            $0.migrationManager.isIronwoodActivated = { false }
            $0.migrationManager.visitKind = { .sync }
            $0.migrationManager.advance = { _ in .notApplicable }
            $0.migrationManager.migrationSyncGateFeed = { AsyncStream { _ in } }
            $0.migrationManager.clearAbandonedNetworkSnapshot = { _ in }
            $0.sdkSynchronizer = .mocked(
                stateStream: { Empty().eraseToAnyPublisher() },
                prepareWith: { _, _, _, _ in
                    prepareCount.withValue { $0 += 1 }
                    return .success
                },
                getAllTransactions: { _ in [] },
                isSeedRelevantToAnyDerivedAccount: { _ in true },
                walletAccounts: { [seedDerivedAccount] }
            )
        }
        store.exhaustivity = .off
        return store
    }

    private func drain(_ store: TestStore<Root.State, Root.Action>) async {
        await store.send(.cancelAllRunningEffects)
        await store.skipReceivedActions(strict: false)
        await store.skipInFlightEffects(strict: false)
    }

    @Test func foregroundDuringOnboardingLeavesOnboardingInCharge() async {
        let prepareCount = LockIsolated(0)
        let store = makeStore(destination: .onboarding, prepareCount: prepareCount)

        await store.send(.initialization(.appDelegate(.willEnterForeground)))
        await store.skipReceivedActions(strict: false)

        #expect(store.state.destinationState.destination == .onboarding)
        #expect(store.state.isRestoringWallet == false)
        #expect(prepareCount.value == 0)

        await drain(store)
    }

    /// Control: outside onboarding the same foreground still re-runs the launch chain, so the
    /// assertions above are about the guard and not about a fixture that never reaches it.
    @Test func foregroundOutsideOnboardingStillReinitializes() async {
        let prepareCount = LockIsolated(0)
        let store = makeStore(destination: .welcome, prepareCount: prepareCount)

        await store.send(.initialization(.appDelegate(.willEnterForeground)))
        await store.skipReceivedActions(strict: false)

        #expect(store.state.isRestoringWallet == true)

        await drain(store)
    }
}
