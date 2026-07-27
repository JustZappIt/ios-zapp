//
//  OnboardingSeedBackupCaptureTests.swift
//  zodlTests
//

import ComposableArchitecture
import Testing
@testable import zodl_internal

/// The onboarding seed-backup screen watches `UIScreen.capturedDidChangeNotification`, which
/// only fires on a TRANSITION. A recording that was already running when the screen opened never
/// produces one, so tapping Reveal used to hand over all 24 words to the recording.
@Suite struct OnboardingSeedBackupCaptureTests {
    private static let phrase = (1...24).map { "word\($0)" }.joined(separator: " ")

    private func storedWallet() -> StoredWallet {
        StoredWallet(
            language: .english,
            seedPhrase: SeedPhrase(Self.phrase),
            version: 1,
            hasUserPassedPhraseBackupTest: true
        )
    }

    @MainActor @Test func revealIsRefusedWhileTheScreenIsAlreadyBeingRecorded() async {
        let store = TestStore(initialState: OnboardingSeedBackup.State.initial) {
            OnboardingSeedBackup()
        } withDependencies: {
            $0.screenCapture.isCaptured = { true }
            $0.walletStorage.exportWallet = { self.storedWallet() }
        }
        store.exhaustivity = .off

        await store.send(.revealTapped)

        #expect(store.state.words.isEmpty)
        #expect(!store.state.isRevealed)
        #expect(!store.state.isLoading)
        #expect(store.state.isBlockedByScreenCapture)
    }

    @MainActor @Test func revealProceedsWhenNothingIsRecording() async {
        let store = TestStore(initialState: OnboardingSeedBackup.State.initial) {
            OnboardingSeedBackup()
        } withDependencies: {
            $0.screenCapture.isCaptured = { false }
            $0.walletStorage.exportWallet = { self.storedWallet() }
        }
        store.exhaustivity = .off

        await store.send(.revealTapped)
        await store.receive(\.seedLoaded)

        #expect(store.state.words.count == 24)
        #expect(store.state.isRevealed)
        #expect(!store.state.isBlockedByScreenCapture)
    }

    /// The refusal must not outlive the recording: stopping it and tapping again reveals.
    @MainActor @Test func theRefusalClearsOnTheNextAttempt() async {
        let isRecording = LockIsolated(true)
        let store = TestStore(initialState: OnboardingSeedBackup.State.initial) {
            OnboardingSeedBackup()
        } withDependencies: {
            $0.screenCapture.isCaptured = { isRecording.value }
            $0.walletStorage.exportWallet = { self.storedWallet() }
        }
        store.exhaustivity = .off

        await store.send(.revealTapped)
        #expect(store.state.isBlockedByScreenCapture)

        isRecording.setValue(false)

        await store.send(.revealTapped)
        await store.receive(\.seedLoaded)

        #expect(!store.state.isBlockedByScreenCapture)
        #expect(store.state.words.count == 24)
    }
}
