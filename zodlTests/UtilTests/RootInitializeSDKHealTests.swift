//
//  RootInitializeSDKHealTests.swift
//  zodlTests
//

@preconcurrency import Combine
import ComposableArchitecture
import Foundation
import Testing
@testable @preconcurrency import ZcashLightClientKit
@testable import zodl_internal

@Suite(.serialized) @MainActor struct RootInitializeSDKHealTests {
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
        calls: LockIsolated<[String]>,
        removedUserDefaultsKeys: LockIsolated<[String]>,
        setUserDefaultsBools: LockIsolated<[String: Bool]>,
        isSeedRelevant: Bool,
        firstPrepareResult: Initializer.InitializationResult = .success,
        walletAccountsResult: [WalletAccount] = [RootInitializeSDKHealTests.seedDerivedAccount],
        firstPrepareError: Error? = nil,
        reprepareError: Error? = nil,
        isStaleWalletHealedAlertPending: Bool = false,
        destination: Root.DestinationState.Destination = .welcome
    ) -> TestStore<Root.State, Root.Action> {
        var initialState = Root.State(
            destinationState: Root.DestinationState(internalDestination: destination),
            exportLogsState: ExportLogs.State(),
            onboardingState: RestoreWalletCoordFlow.State(),
            phraseDisplayState: RecoveryPhraseDisplay.State(),
            walletConfig: .initial,
            welcomeState: Welcome.State()
        )
        initialState.isStaleWalletHealedAlertPending = isStaleWalletHealedAlertPending

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
            $0.databaseFiles = .noOp
            $0.walletStorage = .noOp
            $0.walletStorage.exportWallet = { .placeholder }
            $0.flexaHandler = .noOp
            $0.flexaHandler.signOut = { calls.withValue { $0.append("flexaSignOut") } }
            $0.userStoredPreferences.removeAll = { calls.withValue { $0.append("userPrefsRemoveAll") } }
            $0.readTransactionsStorage = .noOp
            $0.userDefaults.objectForKey = { key in setUserDefaultsBools.value[key] }
            $0.userDefaults.remove = { key in removedUserDefaultsKeys.withValue { $0.append(key) } }
            $0.userDefaults.setValue = { value, key in
                guard let boolValue = value as? Bool else { return }
                setUserDefaultsBools.withValue { $0[key] = boolValue }
            }
            $0.addressBook.allLocalContacts = { _ in (AddressBookContacts.empty, .notAttempted) }
            $0.userMetadataProvider.load = { _ in }
            $0.chatContacts.resetAccount = { _ in calls.withValue { $0.append("chatContactsReset") } }
            $0.zappMessaging.wipe = { calls.withValue { $0.append("zappMessagingWipe") } }
            $0.offramp.invalidateSession = { calls.withValue { $0.append("offrampInvalidate") } }
            $0.sdkSynchronizer = .mocked(
                stateStream: { Empty().eraseToAnyPublisher() },
                prepareWith: { _, _, walletMode, _, _ in
                    let modeLabel: String
                    switch walletMode {
                    case .newWallet: modeLabel = "newWallet"
                    case .restoreWallet: modeLabel = "restoreWallet"
                    case .existingWallet: modeLabel = "existingWallet"
                    }
                    calls.withValue { $0.append("prepareWith(\(modeLabel))") }
                    if walletMode == .restoreWallet {
                        if let reprepareError {
                            throw reprepareError
                        }
                        return .success
                    }
                    if let firstPrepareError {
                        throw firstPrepareError
                    }
                    return firstPrepareResult
                },
                getAllTransactions: { _ in [] },
                wipe: {
                    calls.withValue { $0.append("wipe") }
                    return Just(()).setFailureType(to: Error.self).eraseToAnyPublisher()
                },
                isSeedRelevantToAnyDerivedAccount: { _ in
                    calls.withValue { $0.append("isSeedRelevant") }
                    return isSeedRelevant
                },
                walletAccounts: {
                    calls.withValue { $0.append("walletAccounts") }
                    return walletAccountsResult
                }
            )
        }
        store.exhaustivity = .off
        return store
    }

    private func makeDestinationStore(
        pending: Bool,
        mainQueue: AnySchedulerOf<DispatchQueue> = .immediate
    ) -> TestStore<Root.State, Root.Action> {
        var initialState = Root.State(
            destinationState: Root.DestinationState(),
            exportLogsState: ExportLogs.State(),
            onboardingState: RestoreWalletCoordFlow.State(),
            phraseDisplayState: RecoveryPhraseDisplay.State(),
            walletConfig: .initial,
            welcomeState: Welcome.State()
        )
        initialState.isStaleWalletHealedAlertPending = pending
        let store = TestStore(initialState: initialState) { Root() } withDependencies: {
            $0.defaultInMemoryStorage = InMemoryStorage()
            $0.mainQueue = mainQueue
        }
        store.exhaustivity = .off
        return store
    }

    private func drain(_ store: TestStore<Root.State, Root.Action>) async {
        await store.send(.cancelAllRunningEffects)
        await store.skipReceivedActions(strict: false)
        await store.skipInFlightEffects(strict: false)
    }

    @Test func probeFalseHealClearsZappStateThenWipesAndReprepares() async throws {
        let calls = LockIsolated<[String]>([])
        let removedKeys = LockIsolated<[String]>([])
        let setBools = LockIsolated<[String: Bool]>([:])
        let store = makeStore(
            calls: calls,
            removedUserDefaultsKeys: removedKeys,
            setUserDefaultsBools: setBools,
            isSeedRelevant: false
        )

        await store.send(.initialization(.initializeSDK(.existingWallet)))
        await store.receive(
            { if case .initialization(.staleWalletDatabaseHealed) = $0 { true } else { false } },
            timeout: .seconds(5)
        ) { state in
            state.isRestoringWallet = true
            state.$walletStatus.withLock { $0 = .restoring }
            state.isStaleWalletHealedAlertPending = true
        }

        let recorded = calls.value
        let chatIndex = try #require(recorded.firstIndex(of: "chatContactsReset"))
        let messagingIndex = try #require(recorded.firstIndex(of: "zappMessagingWipe"))
        let wipeIndex = try #require(recorded.firstIndex(of: "wipe"))
        let reprepareIndex = try #require(recorded.firstIndex(of: "prepareWith(restoreWallet)"))
        #expect(chatIndex < wipeIndex)
        #expect(messagingIndex < wipeIndex)
        #expect(wipeIndex < reprepareIndex)
        #expect(removedKeys.value.contains(.appAuthenticationMethod))
        #expect(removedKeys.value.contains(.failedPINAttempts))
        #expect(removedKeys.value.contains(.pinLockoutEndTimestamp))
        #expect(removedKeys.value.contains(.votingConfigOverrideURL))
        #expect(setBools.value[Root.Constants.udIsRestoringWallet] == true)

        await drain(store)
    }

    @Test func seedNotRelevantResultReachesKnownStaleHeal() async throws {
        let calls = LockIsolated<[String]>([])
        let store = makeStore(
            calls: calls,
            removedUserDefaultsKeys: LockIsolated([]),
            setUserDefaultsBools: LockIsolated([:]),
            isSeedRelevant: false,
            firstPrepareResult: .seedNotRelevant
        )

        await store.send(.initialization(.initializeSDK(.existingWallet)))
        await store.receive(
            { if case .initialization(.staleWalletDatabaseHealed) = $0 { true } else { false } },
            timeout: .seconds(5)
        ) { state in
            state.isRestoringWallet = true
            state.$walletStatus.withLock { $0 = .restoring }
            state.isStaleWalletHealedAlertPending = true
        }

        let recorded = calls.value
        let wipeIndex = try #require(recorded.firstIndex(of: "wipe"))
        let beforeWipe = recorded[..<wipeIndex]
        #expect(!beforeWipe.contains("isSeedRelevant"))
        // The fork still needs one account read to clear account-scoped chat contacts. A
        // second read here would mean the derived-account probe was incorrectly taken.
        #expect(beforeWipe.filter { $0 == "walletAccounts" }.count == 1)
        await drain(store)
    }

    @Test func initializerSeedMismatchErrorReachesKnownStaleHeal() async throws {
        let calls = LockIsolated<[String]>([])
        let store = makeStore(
            calls: calls,
            removedUserDefaultsKeys: LockIsolated([]),
            setUserDefaultsBools: LockIsolated([:]),
            isSeedRelevant: false,
            firstPrepareError: ZcashError.initializerSeedMismatch
        )

        await store.send(.initialization(.initializeSDK(.existingWallet)))
        await store.receive(
            { if case .initialization(.staleWalletDatabaseHealed) = $0 { true } else { false } },
            timeout: .seconds(5)
        ) { state in
            state.isRestoringWallet = true
            state.$walletStatus.withLock { $0 = .restoring }
            state.isStaleWalletHealedAlertPending = true
        }

        let recorded = calls.value
        let wipeIndex = try #require(recorded.firstIndex(of: "wipe"))
        let beforeWipe = recorded[..<wipeIndex]
        #expect(!beforeWipe.contains("isSeedRelevant"))
        #expect(beforeWipe.filter { $0 == "walletAccounts" }.count == 1)
        #expect(store.state.alert == nil)
        #expect(store.state.appInitializationState != .failed)
        await drain(store)
    }

    @Test func relevantSeedSkipsHeal() async {
        let calls = LockIsolated<[String]>([])
        let store = makeStore(
            calls: calls,
            removedUserDefaultsKeys: LockIsolated([]),
            setUserDefaultsBools: LockIsolated([:]),
            isSeedRelevant: true
        )

        await store.send(.initialization(.initializeSDK(.existingWallet)))
        await store.receive(
            { if case .initialization(.initializationSuccessfullyDone) = $0 { true } else { false } },
            timeout: .seconds(5)
        )
        #expect(!calls.value.contains("wipe"))
        #expect(!store.state.isRestoringWallet)
        #expect(store.state.alert == nil)
        await drain(store)
    }

    @Test func viewOnlyDatabaseIsNeverWiped() async {
        let calls = LockIsolated<[String]>([])
        let viewOnlyAccount = WalletAccount(
            Account(
                id: AccountUUID(id: [UInt8](repeating: 0x03, count: 16)),
                name: "Keystone",
                keySource: "keystone",
                seedFingerprint: nil,
                hdAccountIndex: nil,
                ufvk: nil,
                uivk: nil
            )
        )
        let store = makeStore(
            calls: calls,
            removedUserDefaultsKeys: LockIsolated([]),
            setUserDefaultsBools: LockIsolated([:]),
            isSeedRelevant: false,
            walletAccountsResult: [viewOnlyAccount]
        )

        await store.send(.initialization(.initializeSDK(.existingWallet)))
        await store.receive(
            { if case .initialization(.initializationFailed) = $0 { true } else { false } },
            timeout: .seconds(5)
        )
        #expect(!calls.value.contains("wipe"))
        #expect(!calls.value.contains("chatContactsReset"))
        await drain(store)
    }

    @Test func reprepareFailureReleasesLatchBeforeRecoveryReentry() async throws {
        let calls = LockIsolated<[String]>([])
        let store = makeStore(
            calls: calls,
            removedUserDefaultsKeys: LockIsolated([]),
            setUserDefaultsBools: LockIsolated([:]),
            isSeedRelevant: false,
            reprepareError: ReprepareStubError()
        )

        await store.send(.initialization(.initializeSDK(.existingWallet)))
        await store.receive(
            { if case .initialization(.initializeSDKFinished) = $0 { true } else { false } },
            timeout: .seconds(5)
        ) {
            $0.isInitializingSDK = false
        }
        await store.receive(
            { if case .initialization(.checkWalletInitialization) = $0 { true } else { false } },
            timeout: .seconds(5)
        )
        #expect(!store.state.isInitializingSDK)
        #expect(store.state.alert == nil)
        await drain(store)
    }

    @Test func pendingAlertPresentsOnceHomeSettles() async {
        let store = makeDestinationStore(pending: true)
        await store.send(.destination(.updateDestination(.home)))
        await store.receive(
            { if case .initialization(.presentStaleWalletHealedAlert) = $0 { true } else { false } },
            timeout: .seconds(5)
        ) { state in
            state.isStaleWalletHealedAlertPending = false
            state.alert = AlertState.staleWalletDatabaseHealed()
        }
        await store.send(.destination(.updateDestination(.home)))
        #expect(!store.state.isStaleWalletHealedAlertPending)
        await drain(store)
    }

    @Test func leavingHomeBeforeDeliveryKeepsAlertPending() async {
        let testQueue = DispatchQueue.test
        let store = makeDestinationStore(pending: true, mainQueue: testQueue.eraseToAnyScheduler())
        await store.send(.destination(.updateDestination(.home)))
        await store.send(.destination(.updateDestination(.onboarding)))
        await testQueue.advance(by: .seconds(0.5))
        await store.receive(
            { if case .initialization(.presentStaleWalletHealedAlert) = $0 { true } else { false } },
            timeout: .seconds(5)
        )
        #expect(store.state.alert == nil)
        #expect(store.state.isStaleWalletHealedAlertPending)
        await drain(store)
    }

    @Test func directHomeTransitionHonorsPendingAlert() async {
        let calls = LockIsolated<[String]>([])
        let store = makeStore(
            calls: calls,
            removedUserDefaultsKeys: LockIsolated([]),
            setUserDefaultsBools: LockIsolated([:]),
            isSeedRelevant: true,
            isStaleWalletHealedAlertPending: true
        )
        await store.send(.onboarding(.newWalletSuccessfullyCreated))
        await store.receive(
            { if case .initialization(.presentStaleWalletHealedAlert) = $0 { true } else { false } },
            timeout: .seconds(5)
        ) { state in
            state.isStaleWalletHealedAlertPending = false
            state.alert = AlertState.staleWalletDatabaseHealed()
        }
        #expect(store.state.destinationState.destination == .home)
        await drain(store)
    }

    @Test func healSignalWhileAlreadyHomeSchedulesAlert() async {
        let calls = LockIsolated<[String]>([])
        let store = makeStore(
            calls: calls,
            removedUserDefaultsKeys: LockIsolated([]),
            setUserDefaultsBools: LockIsolated([:]),
            isSeedRelevant: true,
            destination: .home
        )
        await store.send(.initialization(.staleWalletDatabaseHealed)) { state in
            state.isRestoringWallet = true
            state.$walletStatus.withLock { $0 = .restoring }
            state.isStaleWalletHealedAlertPending = true
        }
        await store.receive(
            { if case .initialization(.presentStaleWalletHealedAlert) = $0 { true } else { false } },
            timeout: .seconds(5)
        ) { state in
            state.isStaleWalletHealedAlertPending = false
            state.alert = AlertState.staleWalletDatabaseHealed()
        }
        await drain(store)
    }
}

private struct ReprepareStubError: Error { }
