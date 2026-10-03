//
//  OnboardingProgress.swift
//  Zapp
//
//  Durable onboarding gating, Android's IS_WELCOME_DISMISSED / IS_ONBOARDING_COMPLETED pair
//  (`ZappTabsScaffold.kt`, `WelcomeGateVM.kt`). Launch used to decide by wallet state alone, so a
//  kill anywhere after the wallet was saved landed on Home on the next launch: no seed backup, no
//  username and no app lock. The flow now records how far it got and launch resumes from there.
//
//  One value instead of Android's two booleans: iOS also has to know whether a wallet that is not
//  finished onboarding was created or restored, because the two prepare the SDK differently (a
//  new wallet passes no birthday) and resume on different screens.
//

import Foundation

enum OnboardingProgress: String, Equatable {
    /// A new wallet is about to be (or has been) saved. Written before the keychain write, so a
    /// kill between the two can never leave a saved wallet with no progress at all.
    case walletCreated
    /// A restored wallet is about to be (or has been) saved, written before the keychain write
    /// for the same reason.
    case walletRestored
    /// "Enter Zapp →" on Done, or "Enter Zapp" on Keep open. Cleared only by a wallet reset.
    case completed

    static let storageKey = "zapp_onboardingProgress"

    static func load(_ userDefaults: UserDefaultsClient) -> OnboardingProgress? {
        (userDefaults.objectForKey(storageKey) as? String).flatMap(OnboardingProgress.init(rawValue:))
    }

    static func save(_ progress: OnboardingProgress, _ userDefaults: UserDefaultsClient) {
        userDefaults.setValue(progress.rawValue, storageKey)
    }

    static func clear(_ userDefaults: UserDefaultsClient) {
        userDefaults.remove(storageKey)
    }
}

/// Where a launch with a saved wallet goes, given what onboarding recorded.
enum OnboardingLaunchDecision: Equatable {
    /// Onboarding is finished: the existing launch chain runs and lands on Home.
    case proceed(backfillsCompletion: Bool)
    case resume(OnboardingResumePlan)
}

struct OnboardingResumePlan: Equatable {
    enum Step: Equatable {
        /// Create path, before "I've saved it". Android's `walletReadyTarget` → `WALLET_SEED`.
        case seedBackup
        /// Create path, after the seed was backed up. Android's `MSG_INTRO`.
        case messagingIntro
        /// Restore path. Android's `recoveryTarget` → `SEED_CONFIRM`.
        case seedConfirm
    }

    var step: Step
    /// Prepare the SDK right away. Nil when preparing waits for the seed backup's continue, as it
    /// does on a fresh create.
    var initializeNow: WalletInitMode?
    /// Handed to the seed backup step, which provisions the wallet when the user continues.
    var deferredProvisioning: RestoreWalletCoordFlow.WalletProvisioningMode?
    /// Raise the restoring status now, as the `.filesMissing` launch does. Only for a wallet of
    /// unknown origin: the restore flow raises it itself on Keep open.
    var marksWalletRestoring = false
}

extension OnboardingProgress {
    /// The launch rule for a wallet that is in the keychain.
    ///
    /// Upgrade path: builds before this gate wrote no progress, so a missing value is ambiguous.
    /// Every shipped Zapp build ends onboarding on the app lock step (it landed on 2026-07-23,
    /// before the first TestFlight build), and that step runs only after the chat identity was
    /// derived, so a stored app lock method means the install finished onboarding. The method is
    /// read from storage directly: `AppSecurityClient.authenticationMethod()` falls back to
    /// biometric for any wallet, which would make every interrupted onboarding look finished.
    ///
    /// Anything else with no progress, such as an install interrupted on an older build or a
    /// reinstall over a keychain wallet, is of unknown origin and resumes on the create path.
    /// It keeps the stored birthday (`.restoreWallet`), never the new-wallet nil birthday, so
    /// funds received since the wallet's real birthday cannot be skipped.
    static func launchDecision(
        progress: OnboardingProgress?,
        hasStoredAppLock: Bool,
        areDbFilesPresent: Bool,
        hasPassedBackup: Bool
    ) -> OnboardingLaunchDecision {
        switch progress {
        case .completed:
            return .proceed(backfillsCompletion: false)

        case .none where hasStoredAppLock:
            return .proceed(backfillsCompletion: true)

        case .walletRestored:
            return .resume(
                OnboardingResumePlan(
                    step: .seedConfirm,
                    initializeNow: areDbFilesPresent ? .existingWallet : .restoreWallet
                )
            )

        case .walletCreated, .none:
            let isKnownNewWallet = progress == .walletCreated
            if !hasPassedBackup {
                // A wallet that was never backed up is never treated as a restore: it goes back
                // to its seed phrase, and the SDK is prepared when the user confirms it.
                return .resume(
                    OnboardingResumePlan(
                        step: .seedBackup,
                        initializeNow: areDbFilesPresent ? .existingWallet : nil,
                        deferredProvisioning: areDbFilesPresent ? nil : (isKnownNewWallet ? .created : .restored),
                        marksWalletRestoring: !isKnownNewWallet && !areDbFilesPresent
                    )
                )
            }
            let initMode: WalletInitMode = areDbFilesPresent
                ? .existingWallet
                : (isKnownNewWallet ? .newWallet : .restoreWallet)
            return .resume(
                OnboardingResumePlan(
                    step: .messagingIntro,
                    initializeNow: initMode,
                    marksWalletRestoring: !isKnownNewWallet && !areDbFilesPresent
                )
            )
        }
    }
}
