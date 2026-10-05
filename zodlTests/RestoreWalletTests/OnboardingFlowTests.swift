//
//  OnboardingFlowTests.swift
//  zodlTests
//
//  The onboarding coordinator's half of the parity pass: progress is recorded ahead of every
//  keychain write and completed only at "Enter Zapp", Tor is on for created and restored wallets,
//  the Zapp restore flow runs seed entry → birthday → restoring → seed confirm → username, and a
//  resumed onboarding rebuilds the right step.
//
//  `RestoreWalletCoordFlow.State` is not Equatable, so these drive a plain `Store` (as the other
//  suites in this folder do) and record the actions the flow hands to Root alongside its storage
//  writes.
//

import ComposableArchitecture
import Foundation
import Testing
@testable import zodl_internal
@preconcurrency import ZcashLightClientKit

@Suite(.serialized, .timeLimit(.minutes(1))) @MainActor struct OnboardingFlowTests {
    /// Every side effect the flow has on storage, and every action it hands up, in order.
    private enum Event: Equatable {
        case progress(String)
        case torFlag(Bool)
        case torEnabled(Bool)
        case importWallet(BlockHeight?)
        case backupPassed
        case provisioned(RestoreWalletCoordFlow.WalletProvisioningMode)
        case newWalletSuccessfullyCreated
        case restoreFlowCompleted(keepsScreenOn: Bool)
        case restoreSucceeded
        case restoreFailed
    }

    private func makeStore(
        _ state: RestoreWalletCoordFlow.State,
        events: LockIsolated<[Event]>,
        importFails: LockIsolated<Bool> = LockIsolated(false)
    ) -> StoreOf<RestoreWalletCoordFlow> {
        Store(initialState: state) {
            CombineReducers {
                RestoreWalletCoordFlow()
                Reduce<RestoreWalletCoordFlow.State, RestoreWalletCoordFlow.Action> { _, action in
                    let event: Event? = switch action {
                    case .walletProvisioned(let mode): .provisioned(mode)
                    case .newWalletSuccessfullyCreated: .newWalletSuccessfullyCreated
                    case .restoreFlowCompleted(let keepsScreenOn): .restoreFlowCompleted(keepsScreenOn: keepsScreenOn)
                    case .restoreSucceeded: .restoreSucceeded
                    case .restoreFailed: .restoreFailed
                    default: nil
                    }
                    if let event {
                        events.withValue { $0.append(event) }
                    }
                    return .none
                }
            }
        } withDependencies: {
            $0.mnemonic = .noOp
            $0.mnemonic.randomMnemonic = { "new phrase" }
            $0.continuousClock = ImmediateClock()
            $0.zcashSDKEnvironment = .testnet
            $0.appSecurity.authenticationMethod = { .pin }
            $0.userDefaults = UserDefaultsClient(
                objectForKey: { _ in nil },
                remove: { _ in },
                setValue: { value, key in
                    if key == OnboardingProgress.storageKey, let value = value as? String {
                        events.withValue { $0.append(.progress(value)) }
                    }
                }
            )
            $0.sdkSynchronizer = .noOp
            $0.sdkSynchronizer.torEnabled = { enabled in events.withValue { $0.append(.torEnabled(enabled)) } }
            $0.walletStorage = .noOp
            $0.walletStorage.importTorSetupFlag = { flag in events.withValue { $0.append(.torFlag(flag)) } }
            $0.walletStorage.importWallet = { _, birthday, _, _ in
                if importFails.value { throw ZcashError.synchronizerNotPrepared }
                events.withValue { $0.append(.importWallet(birthday)) }
            }
            $0.walletStorage.markUserPassedPhraseBackupTest = { _ in events.withValue { $0.append(.backupPassed) } }
        }
    }

    /// Polls until the effect chain lands. No deadline: a slow CI runner gets there later, not
    /// differently, and the suite's `.timeLimit` is the only clock.
    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        while !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func index(of event: Event, in events: LockIsolated<[Event]>) -> Int? {
        events.value.firstIndex(of: event)
    }

    // MARK: - Create

    @Test func createRecordsProgressBeforeTheKeychainWriteAndTurnsTorOn() async {
        let events = LockIsolated<[Event]>([])
        let store = makeStore(RestoreWalletCoordFlow.State(), events: events)

        store.send(.createNewWalletRequested)
        await waitUntil { store.state.path.last?.is(\.seedBackup) == true }

        let progressIndex = index(of: .progress(OnboardingProgress.walletCreated.rawValue), in: events)
        let importIndex = events.value.firstIndex { if case .importWallet = $0 { true } else { false } }
        #expect(progressIndex != nil && importIndex != nil && (progressIndex ?? .max) < (importIndex ?? .min))
        #expect(events.value.contains(.torFlag(true)))
        #expect(events.value.contains(.torEnabled(true)))
        #expect(store.state.pendingProvisioning == .created)
        #expect(store.state.path.last?.is(\.seedBackup) == true)
        #expect(!events.value.contains(.progress(OnboardingProgress.completed.rawValue)))
    }

    @Test func seedBackupProvisionsTheDeferredWalletOnce() async {
        let events = LockIsolated<[Event]>([])
        var state = RestoreWalletCoordFlow.State()
        state.pendingProvisioning = .created
        state.path.append(.seedBackup(.initial))
        let store = makeStore(state, events: events)
        let id = store.state.path.ids.last ?? 0

        store.send(.path(.element(id: id, action: .seedBackup(.continueTapped))))

        #expect(events.value.filter { $0 == .provisioned(.created) }.count == 1)
        #expect(store.state.pendingProvisioning == nil)
        #expect(store.state.path.last?.is(\.messagingIntro) == true)
        #expect(events.value.contains(.backupPassed))
    }

    /// A resumed create whose wallet is already prepared has nothing pending: continuing must not
    /// prepare it a second time.
    @Test func seedBackupWithNothingPendingDoesNotProvision() async {
        let events = LockIsolated<[Event]>([])
        var state = RestoreWalletCoordFlow.State()
        state.path.append(.seedBackup(.initial))
        let store = makeStore(state, events: events)
        let id = store.state.path.ids.last ?? 0

        store.send(.path(.element(id: id, action: .seedBackup(.continueTapped))))

        #expect(store.state.path.last?.is(\.messagingIntro) == true)
        #expect(!events.value.contains { if case .provisioned = $0 { true } else { false } })
    }

    @Test func doneRecordsCompletion() async {
        let events = LockIsolated<[Event]>([])
        var state = RestoreWalletCoordFlow.State()
        state.path.append(.done(OnboardingDone.State(mode: .pin)))
        let store = makeStore(state, events: events)
        let id = store.state.path.ids.last ?? 0

        store.send(.path(.element(id: id, action: .done(.enterTapped))))

        #expect(events.value == [.progress(OnboardingProgress.completed.rawValue), .newWalletSuccessfullyCreated])
    }

    // MARK: - Restore

    @Test func bothRestoreEntriesOpenTheZappSeedEntry() async {
        let store = makeStore(RestoreWalletCoordFlow.State(), events: LockIsolated([]))

        store.send(.importExistingWallet)

        #expect(store.state.path.count == 1)
        #expect(store.state.path.last?.is(\.restoreSeedEntry) == true)
    }

    @Test func restoreRunsToSeedConfirmWithTorOnAndProgressRecorded() async {
        let events = LockIsolated<[Event]>([])
        var state = RestoreWalletCoordFlow.State()
        var entry = ZappRestoreSeedEntry.State.initial
        entry.words = Array(repeating: "abandon", count: ZappRestoreSeedEntry.wordCount)
        state.path.append(.restoreSeedEntry(entry))
        state.path.append(.restoreBirthday(.initial))
        let store = makeStore(state, events: events)
        let birthdayId = store.state.path.ids.last ?? 0

        store.send(.path(.element(id: birthdayId, action: .restoreBirthday(.restoreRequested(1_234_567)))))
        await waitUntil { events.value.contains(.provisioned(.restored)) }

        #expect(events.value.contains(.torFlag(true)))
        #expect(events.value.contains(.torEnabled(true)))
        #expect(events.value.contains(.importWallet(1_234_567)))
        #expect(events.value.contains(.backupPassed))
        let progressIndex = index(of: .progress(OnboardingProgress.walletRestored.rawValue), in: events)
        let importIndex = index(of: .importWallet(1_234_567), in: events)
        #expect(progressIndex != nil && importIndex != nil && (progressIndex ?? .max) < (importIndex ?? .min))
        #expect(events.value.contains(.provisioned(.restored)))

        // seed entry, birthday, seed confirm: the restoring step is replaced, not stacked.
        #expect(store.state.path.count == 3)
        #expect(store.state.path.last.flatMap { $0.seedBackup?.kind } == .confirm)
        #expect(store.state.path.first.flatMap { $0.restoreSeedEntry?.words.allSatisfy(\.isEmpty) } == true)
        #expect(store.state.restoreRequest == nil)
        #expect(store.state.isImportingWallet)
    }

    @Test func restoreFailureOffersRetry() async {
        let events = LockIsolated<[Event]>([])
        let importFails = LockIsolated(true)
        var state = RestoreWalletCoordFlow.State()
        state.path.append(.restoreSeedEntry(.initial))
        state.path.append(.restoreBirthday(.initial))
        let store = makeStore(state, events: events, importFails: importFails)
        let birthdayId = store.state.path.ids.last ?? 0

        store.send(.path(.element(id: birthdayId, action: .restoreBirthday(.restoreRequested(1_000_000)))))
        await waitUntil { events.value.contains(.restoreFailed) }

        let restoringId = store.state.path.ids.last ?? 0
        #expect(store.state.path[id: restoringId, case: \.restoring]?.errorMessage != nil)

        importFails.setValue(false)
        store.send(.path(.element(id: restoringId, action: .restoring(.retryTapped))))
        await waitUntil { events.value.contains(.restoreSucceeded) }

        #expect(events.value.contains(.importWallet(1_000_000)))
        #expect(store.state.path.last.flatMap { $0.seedBackup?.kind } == .confirm)
    }

    @Test func seedConfirmLeadsToUsernameAndBackReturnsToIt() async {
        var state = RestoreWalletCoordFlow.State()
        var confirm = OnboardingSeedBackup.State.confirm
        confirm.isRevealed = true
        confirm.isConfirmed = true
        state.path.append(.seedBackup(confirm))
        let store = makeStore(state, events: LockIsolated([]))
        let confirmId = store.state.path.ids.last ?? 0

        store.send(.path(.element(id: confirmId, action: .seedBackup(.continueTapped))))
        #expect(store.state.path.last?.is(\.chatUsername) == true)

        let usernameId = store.state.path.ids.last ?? 0
        store.send(.path(.element(id: usernameId, action: .chatUsername(.backTapped))))
        await waitUntil { store.state.path.count == 1 }
        #expect(store.state.path.count == 1)
        #expect(store.state.path.last?.is(\.seedBackup) == true)
    }

    @Test func restoreAppLockEndsOnKeepOpenAndEnterCompletes() async {
        let events = LockIsolated<[Event]>([])
        var state = RestoreWalletCoordFlow.State()
        state.path.append(.seedBackup(.confirm))
        state.path.append(.appLockSetup(.initial))
        let store = makeStore(state, events: events)
        let lockId = store.state.path.ids.last ?? 0

        store.send(.path(.element(id: lockId, action: .appLockSetup(.setupFinished))))
        #expect(store.state.path.last?.is(\.keepOpen) == true)
        #expect(!store.state.path.contains { $0.is(\.done) })

        let keepOpenId = store.state.path.ids.last ?? 0
        store.send(.path(.element(id: keepOpenId, action: .keepOpen(.keepScreenOnToggled))))
        store.send(.path(.element(id: keepOpenId, action: .keepOpen(.enterTapped))))

        #expect(events.value == [
            .progress(OnboardingProgress.completed.rawValue),
            .restoreFlowCompleted(keepsScreenOn: true)
        ])
    }

    // MARK: - Resume

    @Test func resumeRebuildsEachStep() async {
        let store = makeStore(RestoreWalletCoordFlow.State(), events: LockIsolated([]))

        store.send(.resume(OnboardingResumePlan(step: .seedBackup, deferredProvisioning: .created)))
        #expect(store.state.path.count == 1)
        #expect(store.state.path.last.flatMap { $0.seedBackup?.kind } == .backup)
        #expect(store.state.pendingProvisioning == .created)
        #expect(!store.state.isImportingWallet)

        store.send(.resume(OnboardingResumePlan(step: .messagingIntro, initializeNow: .existingWallet)))
        #expect(store.state.path.count == 1)
        #expect(store.state.path.last?.is(\.messagingIntro) == true)
        #expect(store.state.pendingProvisioning == nil)

        store.send(.resume(OnboardingResumePlan(step: .seedConfirm, initializeNow: .restoreWallet)))
        #expect(store.state.path.count == 1)
        #expect(store.state.path.last.flatMap { $0.seedBackup?.kind } == .confirm)
        #expect(store.state.isImportingWallet)
    }

    /// Kill after the username: the identity was derived before the kill, so the resumed flow goes
    /// from the messaging intro straight to the app lock instead of asking for a name it would
    /// ignore.
    @Test func identityThatSurvivedSkipsTheUsername() async {
        var state = RestoreWalletCoordFlow.State()
        state.path.append(.messagingIntro(.initial))
        let store = makeStore(state, events: LockIsolated([]))

        store.send(.chatIdentityAvailable)
        #expect(store.state.path.last?.is(\.appLockSetup) == true)

        // Repeated state ticks do not stack a second app lock.
        store.send(.chatIdentityAvailable)
        #expect(store.state.path.count == 2)
    }

    @Test func identityDoesNotSkipTheSeedConfirm() async {
        var state = RestoreWalletCoordFlow.State()
        state.path.append(.seedBackup(.confirm))
        let store = makeStore(state, events: LockIsolated([]))

        store.send(.chatIdentityAvailable)
        #expect(store.state.path.count == 1)
    }
}
