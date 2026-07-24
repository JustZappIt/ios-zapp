//
//  RestoreWalletCoordFlowCoordinator.swift
//  Zashi
//
//  Created by Lukáš Korba on 27-03-2025.
//

import ComposableArchitecture

extension RestoreWalletCoordFlow {
    func coordinatorReduce() -> Reduce<RestoreWalletCoordFlow.State, RestoreWalletCoordFlow.Action> {
        Reduce { state, action in
            switch action {
                
                // MARK: - Self

            case .dismissDestination:
                state.path.removeAll()
                state.landingStep = .welcome
                return .none

            case .landingGetStartedTapped:
                state.landingStep = .walletIntro
                return .none

            case .landingContinueTapped:
                state.landingStep = .walletChoice
                return .none

            case .landingBackTapped:
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
                
            case .restoreCancelTapped:
                state.isTorSheetPresented = false
                return .none

            case .createNewWalletRequested:
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
                state.path.append(.seedBackup(.initial))
                return .none

            case .importExistingWallet:
                state.path.append(.recoverySeedPhraseEntry(state))
                return .none
                
            case .resolveRestoreTapped:
                state.isTorOn = false
                state.isTorSheetPresented = true
                return .none

            case .resolveRestore:
                guard let birthday = state.birthday else {
                    return .none
                }
                do {
                    let seedPhrase = state.words.joined(separator: " ")
                    
                    // validate the seed
                    try mnemonic.isValid(seedPhrase)

                    try walletStorage.importWallet(seedPhrase, birthday, .english, false)
                    
                    // update the backup phrase validation flag
                    try walletStorage.markUserPassedPhraseBackupTest(true)

                    state.path.append(.chatUsername(ChatUsernameEntry.State.initial))
                    return .send(.walletProvisioned(.restored))
                } catch {
                    return .send(.failedToRecover(error.toZcashError()))
                }
                
            case .resolveRestoreRequested:
                state.isTorSheetPresented = false
                let isTorOn = state.isTorOn
                try? walletStorage.importTorSetupFlag(isTorOn)
                return .merge(
                    .send(.resolveRestore),
                    .run { _ in try? await sdkSynchronizer.torEnabled(isTorOn) }
                )

                // MARK: Recovery Seed Phrase Entry
                
            case .path(.element(id: _, action: .chatUsername(.continueTapped))):
                state.path.append(.identityDerivation(.initial))
                return .none

            case .path(.element(id: _, action: .seedBackup(.continueTapped))):
                do {
                    try walletStorage.markUserPassedPhraseBackupTest(true)
                } catch {
                    state.alert = .cantMarkPhraseBackedUp(error.toZcashError())
                    return .none
                }
                state.path.append(.chatUsername(ChatUsernameEntry.State.initial))
                return .send(.walletProvisioned(.created))

            case .path(.element(id: _, action: .identityDerivation(.identityReady))):
                state.path.append(.appLockSetup(.initial))
                return .none

            case .path(.element(id: _, action: .appLockSetup(.setupFinished))):
                if state.isImportingWallet {
                    state.path.append(.restoreInfo(RestoreInfo.State.initial))
                    return .send(.successfullyRecovered)
                }
                return .send(.newWalletSuccessfullyCreated)

            case .path(.element(id: _, action: .recoverySeedPhraseEntry(.nextTapped))):
                for element in state.path {
                    if case .recoverySeedPhraseEntry(let recoverySeedPhraseEntryState) = element {
                        state.words = recoverySeedPhraseEntryState.words
                    }
                }
                state.path.append(.walletBirthday(WalletBirthday.State.initial))
                return .none
                
            case .path(.element(id: _, action: .recoverySeedPhraseEntry(.helpSheetRequested))),
                .path(.element(id: _, action: .estimatedBirthday(.helpSheetRequested))):
                state.isHelpSheetPresented.toggle()
                return .none

                // MARK: - Wallet Birthday

            case .path(.element(id: _, action: .walletBirthday(.helpSheetRequested))):
                state.isHelpSheetPresented.toggle()
                return .none

            case .path(.element(id: _, action: .walletBirthday(.estimateHeightTapped))):
                state.path.append(.estimateBirthdaysDate(WalletBirthday.State.initial))
                return .none

            case .path(.element(id: _, action: .walletBirthday(.restoreTapped))):
                for element in state.path {
                    if case .walletBirthday(let walletBirthdayState) = element {
                        state.birthday = walletBirthdayState.estimatedHeight
                        return .send(.resolveRestoreTapped)
                    }
                }
                return .none
                
            case .path(.element(id: _, action: .estimateBirthdaysDate(.helpSheetRequested))):
                state.isHelpSheetPresented.toggle()
                return .none

            case .path(.element(id: _, action: .estimateBirthdaysDate(.estimateHeightReady))):
                for element in state.path {
                    if case .estimateBirthdaysDate(let estimateBirthdaysDateState) = element {
                        state.path.append(.estimatedBirthday(estimateBirthdaysDateState))
                    }
                }
                return .none
                
            case .path(.element(id: _, action: .estimatedBirthday(.restoreTapped))):
                for element in state.path {
                    if case .estimatedBirthday(let estimatedBirthdayState) = element {
                        state.birthday = estimatedBirthdayState.estimatedHeight
                        return .send(.resolveRestoreTapped)
                    }
                }
                return .none

            default: return .none
            }
        }
    }

    private func createWalletEffect() -> Effect<Action> {
        .run { send in
            // Give SwiftUI a render pass so the loading state is visible before
            // seed generation and encrypted persistence begin.
            await Task.yield()
            do {
                let newRandomPhrase = try mnemonic.randomMnemonic()
                let birthday = zcashSDKEnvironment.latestCheckpoint()
                try walletStorage.importWallet(newRandomPhrase, birthday, .english, false)
                // The operation can be faster than one frame on modern devices. Keep
                // the explicit progress state legible instead of flashing through it.
                try? await continuousClock.sleep(for: .milliseconds(900))
                await send(.newWalletPersisted)
            } catch {
                await send(.createNewWalletFailed(error.toZcashError()))
            }
        }
    }
}
