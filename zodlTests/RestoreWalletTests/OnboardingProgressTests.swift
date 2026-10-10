//
//  OnboardingProgressTests.swift
//  zodlTests
//
//  The launch rule of the durable onboarding gate: a saved wallet whose onboarding never finished
//  resumes it at the right step instead of landing on Home, and an install that finished
//  onboarding before the gate existed is not sent back through it.
//

import Testing
@testable import zodl_internal

struct OnboardingProgressTests {
    private func decide(
        _ progress: OnboardingProgress?,
        appLock: Bool = false,
        files: Bool,
        backedUp: Bool
    ) -> OnboardingLaunchDecision {
        OnboardingProgress.launchDecision(
            progress: progress,
            hasStoredAppLock: appLock,
            areDbFilesPresent: files,
            hasPassedBackup: backedUp
        )
    }

    @Test func killAfterCreateReturnsToTheSeedWithoutRestoring() {
        // Saved to the keychain, never prepared, never backed up.
        #expect(
            decide(.walletCreated, files: false, backedUp: false) == .resume(
                OnboardingResumePlan(step: .seedBackup, initializeNow: nil, deferredProvisioning: .created)
            )
        )
    }

    @Test func killAfterSeedBackupResumesAtTheMessagingIntro() {
        #expect(
            decide(.walletCreated, files: true, backedUp: true) == .resume(
                OnboardingResumePlan(step: .messagingIntro, initializeNow: .existingWallet)
            )
        )
    }

    @Test func backedUpNewWalletWithoutDatabaseKeepsTheNewWalletBirthday() {
        #expect(
            decide(.walletCreated, files: false, backedUp: true) == .resume(
                OnboardingResumePlan(step: .messagingIntro, initializeNow: .newWallet)
            )
        )
    }

    @Test func interruptedRestoreResumesAtSeedConfirm() {
        #expect(
            decide(.walletRestored, files: false, backedUp: true) == .resume(
                OnboardingResumePlan(step: .seedConfirm, initializeNow: .restoreWallet)
            )
        )
        #expect(
            decide(.walletRestored, files: true, backedUp: true) == .resume(
                OnboardingResumePlan(step: .seedConfirm, initializeNow: .existingWallet)
            )
        )
    }

    @Test func completedProceeds() {
        #expect(decide(.completed, files: true, backedUp: true) == .proceed(backfillsCompletion: false))
        // Completion wins over everything else, including a reinstall that lost the database.
        #expect(decide(.completed, files: false, backedUp: false) == .proceed(backfillsCompletion: false))
    }

    @Test func upgradeOfAFinishedInstallProceedsAndBackfills() {
        #expect(decide(nil, appLock: true, files: true, backedUp: true) == .proceed(backfillsCompletion: true))
    }

    /// A stale app lock from a previous wallet must not let a new wallet skip its seed backup.
    @Test func appLockDoesNotFinishAWalletThatRecordedProgress() {
        if case .proceed = decide(.walletCreated, appLock: true, files: false, backedUp: false) {
            Issue.record("A recorded create must resume even when an app lock is stored")
        }
    }

    @Test func unknownOriginKeepsTheStoredBirthday() {
        #expect(
            decide(nil, files: false, backedUp: true) == .resume(
                OnboardingResumePlan(step: .messagingIntro, initializeNow: .restoreWallet, marksWalletRestoring: true)
            )
        )
        #expect(
            decide(nil, files: false, backedUp: false) == .resume(
                OnboardingResumePlan(
                    step: .seedBackup,
                    initializeNow: nil,
                    deferredProvisioning: .restored,
                    marksWalletRestoring: true
                )
            )
        )
    }
}
