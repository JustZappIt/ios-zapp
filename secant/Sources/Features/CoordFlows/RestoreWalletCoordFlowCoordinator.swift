//
//  RestoreWalletCoordFlowCoordinator.swift
//  Zashi
//
//  Created by Lukáš Korba on 27-03-2025.
//

import ComposableArchitecture
@preconcurrency import ZcashLightClientKit

extension RestoreWalletCoordFlow {
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func coordinatorReduce() -> Reduce<RestoreWalletCoordFlow.State, RestoreWalletCoordFlow.Action> {
        Reduce { state, action in
            switch action {

                // MARK: - Self

            case .dismissDestination:
                state.path.removeAll()
                state.landingStep = .welcome
                return .none

            case .landingGetStartedTapped:
                state.landingForward = true
                state.landingStep = .walletIntro
                return .none

            case .landingContinueTapped:
                state.landingForward = true
                state.landingStep = .walletChoice
                return .none

            case .landingBackTapped:
                state.landingForward = false
                switch state.landingStep {
                case .welcome:
                    return .none
                case .walletIntro:
                    state.landingStep = .welcome
                case .walletChoice:
                    state.landingStep = .walletIntro
                case .creatingWallet:
                    return .none
                }
                return .none

            case .createNewWalletRequested:
                state.landingForward = true
                state.landingStep = .creatingWallet
                state.walletCreationError = nil
                return createWalletEffect()

            case .createNewWalletRetryTapped:
                state.walletCreationError = nil
                return createWalletEffect()

            case let .createNewWalletFailed(error):
                state.walletCreationError = error.detailedMessage
                return .none

            case .newWalletPersisted:
                state.pendingProvisioning = .created
                state.path.append(.seedBackup(.initial))
                return .none

            case let .resume(plan):
                state.path.removeAll()
                state.pendingProvisioning = plan.deferredProvisioning
                switch plan.step {
                case .seedBackup:
                    state.path.append(.seedBackup(.initial))
                case .messagingIntro:
                    state.path.append(.messagingIntro(.initial))
                case .seedConfirm:
                    state.path.append(.seedBackup(.confirm))
                }
                return .none

            case .chatIdentityAvailable:
                // Android skips the username steps once the identity exists (`isMessagingGate` /
                // `isIdentityGate`). Only a resumed onboarding gets here with one: the identity
                // survived the interruption, and deriving it again would ignore the new name.
                guard let last = state.path.last, last.is(\.messagingIntro) || last.is(\.chatUsername) else {
                    return .none
                }
                state.path.append(.appLockSetup(.initial))
                return .none

                // MARK: - Zapp restore flow

            case .importExistingWallet:
                // Both "I already use Zapp" and Wallet choice → "Restore from phrase" (D3, D6).
                state.path.append(.restoreSeedEntry(.initial))
                return .none

            case let .path(.element(id: id, action: .restoreSeedEntry(.backTapped))),
                let .path(.element(id: id, action: .restoreBirthday(.backTapped))),
                let .path(.element(id: id, action: .chatUsername(.backTapped))):
                state.path.pop(from: id)
                return .none

            case .path(.element(id: _, action: .restoreSeedEntry(.nextTapped))):
                guard state.path.last?.is(\.restoreSeedEntry) == true else {
                    return .none
                }
                state.path.append(.restoreBirthday(.initial))
                return .none

            case .path(.element(id: _, action: .restoreSeedEntry(.helpTapped))),
                .path(.element(id: _, action: .restoreBirthday(.helpTapped))):
                state.isHelpSheetPresented.toggle()
                return .none

            case let .path(.element(id: _, action: .restoreBirthday(.restoreRequested(birthday)))):
                guard
                    state.path.last?.is(\.restoreBirthday) == true,
                    let seedPhrase = state.path.compactMap({ $0.restoreSeedEntry?.seedPhrase }).first
                else {
                    return .none
                }
                let request = RestoreRequest(seedPhrase: seedPhrase, birthday: birthday)
                state.restoreRequest = request
                state.path.append(.restoring(.initial))
                return restoreWalletEffect(request)

            case .path(.element(id: let id, action: .restoring(.retryTapped))):
                guard let request = state.restoreRequest else {
                    return .none
                }
                state.path[id: id, case: \.restoring]?.errorMessage = nil
                return restoreWalletEffect(request)

            case .restoreSucceeded:
                state.restoreRequest = nil
                // The phrase is in the keychain now; the entry grid no longer needs a copy.
                for id in state.path.ids where state.path[id: id]?.is(\.restoreSeedEntry) == true {
                    state.path[id: id, case: \.restoreSeedEntry] = .initial
                }
                if state.path.last?.is(\.restoring) == true {
                    state.path.removeLast()
                }
                state.path.append(.seedBackup(.confirm))
                return .send(.walletProvisioned(.restored))

            case .restoreFailed:
                guard let id = state.path.ids.last, state.path[id: id]?.is(\.restoring) == true else {
                    return .none
                }
                state.path[id: id, case: \.restoring]?.errorMessage = String(localizable: .restoreFlowErrorWalletFailed)
                return .none

            case .path(.element(id: _, action: .keepOpen(.enterTapped))):
                let keepsScreenOn = state.path.compactMap { $0.keepOpen?.keepsScreenOn }.last ?? false
                OnboardingProgress.save(.completed, userDefaults)
                return .send(.restoreFlowCompleted(keepsScreenOn: keepsScreenOn))

                // MARK: - Shared steps

            case let .path(.element(id: id, action: .chatUsername(.continueTapped))):
                // The keyboard's Done key sends this too, and unlike the button it is never
                // disabled. Advancing on an invalid name pushed a derivation screen with no name
                // queued: an endless spinner with no retry and no back, which users escaped by
                // force-quitting and then got asked for the name again in Chats. Done followed by
                // the button also pushed derivation twice, and with it app lock setup twice.
                guard
                    state.path.ids.last == id,
                    state.path[id: id, case: \.chatUsername]?.isValid == true
                else {
                    return .none
                }
                state.path.append(.identityDerivation(.initial))
                return .none

            case let .path(.element(id: id, action: .seedBackup(.continueTapped))):
                guard let seedBackup = state.path[id: id, case: \.seedBackup] else {
                    return .none
                }
                if seedBackup.kind == .confirm {
                    // Restore: the backup flag was set with the import. Username comes next, and
                    // its back button returns here (Android's `RestoreStep.USERNAME` back).
                    state.path.append(.chatUsername(ChatUsernameEntry.State.initial))
                    return .none
                }
                do {
                    try walletStorage.markUserPassedPhraseBackupTest(true)
                } catch {
                    state.alert = .cantMarkPhraseBackedUp(error.toZcashError())
                    return .none
                }
                // Part 2 intro (Android's MessagingPhaseIntro) sits between seed backup and
                // username entry on the create path; the wallet is already committed here.
                state.path.append(.messagingIntro(.initial))
                guard let mode = state.pendingProvisioning else {
                    return .none
                }
                state.pendingProvisioning = nil
                return .send(.walletProvisioned(mode))

            case .path(.element(id: _, action: .messagingIntro(.continueTapped))):
                state.path.append(.chatUsername(ChatUsernameEntry.State.initial))
                return .none

            case .path(.element(id: _, action: .identityDerivation(.identityReady))):
                state.path.append(.appLockSetup(.initial))
                return .none

            case .path(.element(id: _, action: .appLockSetup(.setupFinished))):
                if state.isImportingWallet {
                    // Restore ends on Keep open, with no Done screen (Android's `KEEP_OPEN`).
                    state.path.append(.keepOpen(.initial))
                    return .none
                }
                // Create path ends on the mode-aware Done screen (Android's OnboardingDoneScreen);
                // entering the app is deferred to its CTA.
                let mode: OnboardingDone.Mode = appSecurity.authenticationMethod() == .pin ? .pin : .biometric
                state.path.append(.done(OnboardingDone.State(mode: mode)))
                return .none

            case .path(.element(id: _, action: .done(.enterTapped))):
                OnboardingProgress.save(.completed, userDefaults)
                return .send(.newWalletSuccessfullyCreated)

            default: return .none
            }
        }
    }

    private func createWalletEffect() -> Effect<Action> {
        .merge(
            torByDefaultEffect(),
            .run { send in
                // Give SwiftUI a render pass so the loading state is visible before
                // seed generation and encrypted persistence begin.
                await Task.yield()
                do {
                    let newRandomPhrase = try mnemonic.randomMnemonic()
                    let birthday = zcashSDKEnvironment.latestCheckpoint()
                    // Recorded ahead of the keychain write: a saved wallet with no progress
                    // would be taken for an install from before the onboarding gate.
                    OnboardingProgress.save(.walletCreated, userDefaults)
                    try walletStorage.importWallet(newRandomPhrase, birthday, .english, false)
                    // The operation can be faster than one frame on modern devices. Keep
                    // the explicit progress state legible instead of flashing through it.
                    try? await continuousClock.sleep(for: .milliseconds(900))
                    await send(.newWalletPersisted)
                } catch {
                    await send(.createNewWalletFailed(error.toZcashError()))
                }
            }
        )
    }

    private func restoreWalletEffect(_ request: RestoreRequest) -> Effect<Action> {
        .merge(
            torByDefaultEffect(),
            .run { send in
                await Task.yield()
                do {
                    try mnemonic.isValid(request.seedPhrase)
                    OnboardingProgress.save(.walletRestored, userDefaults)
                    try walletStorage.importWallet(request.seedPhrase, request.birthday, .english, false)
                    // A restored phrase was backed up by definition.
                    try walletStorage.markUserPassedPhraseBackupTest(true)
                    try? await continuousClock.sleep(for: .milliseconds(900))
                    await send(.restoreSucceeded)
                } catch {
                    await send(.restoreFailed(error.toZcashError()))
                }
            }
        )
    }

    /// Tor is on for every created and restored wallet, and the restore-time opt-in is gone
    /// (Android's ZAPP_CHANGES §7, `WalletRepository.createNewWallet` / `restoreWallet`). The flag
    /// is stored for the synchronizer built on the next launch; the runtime call switches the one
    /// already built, as the old restore Tor sheet did. A failed Tor start surfaces through
    /// Root's `.observeTorInit` once the wallet is prepared.
    private func torByDefaultEffect() -> Effect<Action> {
        try? walletStorage.importTorSetupFlag(true)
        return .run { _ in
            try? await sdkSynchronizer.torEnabled(true)
        }
    }
}
