//
//  RootOnboardingGate.swift
//  Zapp
//
//  Launch half of the durable onboarding gate (see `OnboardingProgress`). Android holds a user in
//  onboarding until "Enter Zapp" (`ZappTabsScaffold.kt`); iOS used to decide by wallet state
//  alone, so an interrupted onboarding came back on Home with no seed backup, username or app
//  lock behind it.
//

import ComposableArchitecture
import Foundation

extension Root {
    /// Returns the effect that reopens onboarding where it stopped, or nil when onboarding is
    /// finished and the caller's launch chain should run. Backfills completion for installs that
    /// finished onboarding before the gate existed.
    func resumeOnboardingIfUnfinished(state: inout Root.State, areDbFilesPresent: Bool) -> Effect<Root.Action>? {
        // An unreadable keychain is the caller's to report (`.osStatusError`), not a reason to
        // send the user back through onboarding.
        guard let storedWallet = try? walletStorage.exportWallet() else {
            return nil
        }

        let decision = OnboardingProgress.launchDecision(
            progress: OnboardingProgress.load(userDefaults),
            hasStoredAppLock: userDefaults.objectForKey(.appAuthenticationMethod) != nil,
            areDbFilesPresent: areDbFilesPresent,
            hasPassedBackup: storedWallet.hasUserPassedPhraseBackupTest
        )

        switch decision {
        case .proceed(let backfillsCompletion):
            if backfillsCompletion {
                OnboardingProgress.save(.completed, userDefaults)
            }
            return nil

        case .resume(let plan):
            LoggerProxy.event("Onboarding resumed at \(plan.step)")
            if !areDbFilesPresent {
                state.appInitializationState = .filesMissing
            }
            if plan.marksWalletRestoring {
                state.isRestoringWallet = true
                userDefaults.setValue(true, Constants.udIsRestoringWallet)
                state.$walletStatus.withLock { $0 = .restoring }
            }
            var effects: [Effect<Root.Action>] = [
                .send(.onboarding(.resume(plan))),
                .send(.destination(.updateDestination(.onboarding)))
            ]
            if let mode = plan.initializeNow {
                effects.append(.send(.initialization(.initializeSDK(mode))))
            }
            return .concatenate(effects)
        }
    }
}
