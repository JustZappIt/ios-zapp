//
//  RootOnboardingGateTests.swift
//  zodlTests
//
//  Launch with a saved wallet consults the durable onboarding progress before the launch chain:
//  an unfinished onboarding reopens where it stopped instead of landing on Home with no seed
//  backup, username or app lock, and an install that finished onboarding before the gate existed
//  goes home and has its completion backfilled.
//

@preconcurrency import Combine
import ComposableArchitecture
import Foundation
import Testing
@testable @preconcurrency import ZcashLightClientKit
@testable import zodl_internal

@Suite(.serialized) @MainActor struct RootOnboardingGateTests {
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

    /// A tiny `UserDefaults` so the progress written by the gate can be read back. Only string
    /// values are kept (the gate reads and writes strings); anything else reads back as nil.
    private final class Defaults: Sendable {
        let values = LockIsolated<[String: String]>([:])

        var client: UserDefaultsClient {
            UserDefaultsClient(
                objectForKey: { key in self.values.value[key] },
                remove: { key in self.values.withValue { $0[key] = nil } },
                setValue: { value, key in
                    let string = value as? String
                    self.values.withValue { $0[key] = string }
                }
            )
        }
    }

    private func makeStore(
        defaults: Defaults,
        hasPassedBackup: Bool,
        areDbFilesPresent: Bool,
        prepareModes: LockIsolated<[BlockHeight?]>
    ) -> TestStore<Root.State, Root.Action> {
        let seedDerivedAccount = Self.seedDerivedAccount
        let storedWallet: StoredWallet = {
            var wallet = StoredWallet.placeholder
            wallet.hasUserPassedPhraseBackupTest = hasPassedBackup
            return wallet
        }()
        let initialState = Root.State(
            destinationState: Root.DestinationState(internalDestination: .welcome),
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
            $0.databaseFiles = .noOp
            $0.databaseFiles.areDbFilesPresentFor = { _ in areDbFilesPresent }
            $0.walletStorage = .noOp
            $0.walletStorage.areKeysPresent = { true }
            $0.walletStorage.exportWallet = { storedWallet }
            $0.userDefaults = defaults.client
            $0.readTransactionsStorage = .noOp
            $0.addressBook.allLocalContacts = { _ in (AddressBookContacts.empty, .notAttempted) }
            $0.userMetadataProvider.load = { _ in }
            $0.migrationManager.isIronwoodActivated = { false }
            $0.migrationManager.visitKind = { .sync }
            $0.migrationManager.advance = { _ in .notApplicable }
            $0.migrationManager.migrationSyncGateFeed = { AsyncStream { _ in } }
            $0.migrationManager.clearAbandonedNetworkSnapshot = { _ in }
            // Wallet reset's teardown.
            $0.migrationManager.wipeAllMigrationState = { }
            $0.flexaHandler = .noOp
            $0.userStoredPreferences.removeAll = { }
            $0.userMetadataProvider.reset = { }
            $0.userMetadataProvider.resetAccount = { _ in }
            $0.addressBook.resetAccount = { _ in }
            $0.chatContacts.resetAccount = { _ in }
            $0.zappMessaging.wipe = { }
            $0.offramp.invalidateSession = { }
            #if VOTING_ENABLED
            $0.votingMetadata.reset = { }
            $0.votingMetadata.resetAccount = { _ in }
            #endif
            $0.sdkSynchronizer = .mocked(
                stateStream: { Empty().eraseToAnyPublisher() },
                prepareWith: { _, birthday, _, _ in
                    prepareModes.withValue { $0.append(birthday) }
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

    private func launch(_ store: TestStore<Root.State, Root.Action>) async {
        await store.send(.initialization(.checkWalletInitialization))
        await store.skipReceivedActions(strict: false)
    }

    /// The launch chain prepares and routes from effects; keep taking their actions until the
    /// outcome shows, rather than waiting a fixed time.
    private func waitUntil(
        _ store: TestStore<Root.State, Root.Action>,
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
            await store.skipReceivedActions(strict: false)
        }
    }

    private func drain(_ store: TestStore<Root.State, Root.Action>) async {
        await store.send(.cancelAllRunningEffects)
        await store.skipReceivedActions(strict: false)
        await store.skipInFlightEffects(strict: false)
    }

    /// Kill after create: the wallet is in the keychain, not prepared and not backed up.
    @Test func killAfterCreateReturnsToTheSeedBackup() async {
        let defaults = Defaults()
        defaults.values.setValue([OnboardingProgress.storageKey: OnboardingProgress.walletCreated.rawValue])
        let prepares = LockIsolated<[BlockHeight?]>([])
        let store = makeStore(defaults: defaults, hasPassedBackup: false, areDbFilesPresent: false, prepareModes: prepares)

        await launch(store)

        #expect(store.state.destinationState.destination == .onboarding)
        #expect(store.state.onboardingState.path.last.flatMap { $0.seedBackup?.kind } == .backup)
        #expect(store.state.onboardingState.pendingProvisioning == .created)
        // Not a restore, and not prepared until the phrase is confirmed.
        #expect(store.state.isRestoringWallet == false)
        #expect(prepares.value.isEmpty)

        await drain(store)
    }

    /// Kill after seed backup (or after the username): prepared and backed up, not finished.
    @Test func killAfterSeedBackupReturnsToTheMessagingIntro() async {
        let defaults = Defaults()
        defaults.values.setValue([OnboardingProgress.storageKey: OnboardingProgress.walletCreated.rawValue])
        let prepares = LockIsolated<[BlockHeight?]>([])
        let store = makeStore(defaults: defaults, hasPassedBackup: true, areDbFilesPresent: true, prepareModes: prepares)

        await launch(store)
        await waitUntil(store) { prepares.value.count == 1 }

        #expect(store.state.destinationState.destination == .onboarding)
        #expect(store.state.onboardingState.path.last?.is(\.messagingIntro) == true)
        #expect(prepares.value.count == 1)

        await drain(store)
    }

    @Test func upgradeOfAFinishedInstallGoesHomeAndBackfills() async {
        let defaults = Defaults()
        defaults.values.setValue([String.appAuthenticationMethod: AppAuthenticationMethod.pin.rawValue])
        let prepares = LockIsolated<[BlockHeight?]>([])
        let store = makeStore(defaults: defaults, hasPassedBackup: true, areDbFilesPresent: true, prepareModes: prepares)

        await launch(store)
        await waitUntil(store) { store.state.destinationState.destination == .home }

        #expect(store.state.destinationState.destination == .home)
        #expect(defaults.values.value[OnboardingProgress.storageKey] == OnboardingProgress.completed.rawValue)

        await drain(store)
    }

    @Test func finishedOnboardingGoesHome() async {
        let defaults = Defaults()
        defaults.values.setValue([OnboardingProgress.storageKey: OnboardingProgress.completed.rawValue])
        let prepares = LockIsolated<[BlockHeight?]>([])
        let store = makeStore(defaults: defaults, hasPassedBackup: true, areDbFilesPresent: true, prepareModes: prepares)

        await launch(store)
        await waitUntil(store) { store.state.destinationState.destination == .home }

        #expect(store.state.destinationState.destination == .home)

        await drain(store)
    }

    @Test func noWalletClearsStaleProgress() async {
        let defaults = Defaults()
        defaults.values.setValue([OnboardingProgress.storageKey: OnboardingProgress.completed.rawValue])
        let store = makeStore(defaults: defaults, hasPassedBackup: false, areDbFilesPresent: false, prepareModes: LockIsolated([]))

        await store.send(.initialization(.respondToWalletInitializationState(.uninitialized)))

        #expect(defaults.values.value[OnboardingProgress.storageKey] == nil)

        await drain(store)
    }

    @Test func walletResetClearsProgress() async {
        let defaults = Defaults()
        defaults.values.setValue([OnboardingProgress.storageKey: OnboardingProgress.completed.rawValue])
        let store = makeStore(defaults: defaults, hasPassedBackup: true, areDbFilesPresent: true, prepareModes: LockIsolated([]))

        await store.send(.resetZashiSDKSucceeded)

        #expect(defaults.values.value[OnboardingProgress.storageKey] == nil)

        await drain(store)
    }
}
