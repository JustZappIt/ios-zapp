//
//  ChatContactProfileParityTests.swift
//  zodlTests
//
//  Phase 8 — contacts & profile parity. The assertions that matter here are the ones a
//  reviewer cannot check by looking at a screenshot: that the typed addresses round-trip
//  through the same `walletAddresses` keys Android writes, that a scan lands in the field
//  that asked for it, and — above all — that neither secret can be read without the app
//  lock and that both are gone the moment the app stops being frontmost.
//

import ComposableArchitecture
import Foundation
import Testing
@testable import zodl_internal

@Suite(.serialized) struct ChatContactFormParityTests {
    private let peerKey = String(repeating: "a", count: 64)

    // MARK: - Typed addresses

    @MainActor @Test func typedAddressesSaveUnderAndroidsWalletAddressKeys() async {
        let store = TestStore(initialState: ChatContactForm.State()) {
            ChatContactForm()
        }
        store.exhaustivity = .off

        await store.send(.nameChanged("Ada"))
        await store.send(.publicKeyChanged(peerKey))
        await store.send(.transparentAddressChanged("  t1transparent  "))
        await store.send(.evmAddressChanged("0xEvm"))
        await store.send(.solanaAddressChanged("SolanaAddr"))

        let addresses = store.state.walletAddresses

        #expect(addresses[ChatContact.AddrType.transparent] == "t1transparent")
        #expect(addresses[ChatContact.AddrType.evm] == "0xEvm")
        #expect(addresses[ChatContact.AddrType.solana] == "SolanaAddr")
    }

    @MainActor @Test func editingSeedsTheTypedFieldsAndRevealsTheSection() async {
        let contact = ChatContact(
            publicKey: peerKey,
            name: "Ada",
            walletAddresses: [
                ChatContact.AddrType.evm: "0xEvm",
                // A type this build does not know about must survive a round-trip untouched.
                "future_chain": "xyz"
            ]
        )
        let state = ChatContactForm.State(existing: contact)

        #expect(state.evmAddress == "0xEvm")
        #expect(state.transparentAddress.isEmpty)
        #expect(state.showsAdditionalAddresses)
        #expect(state.walletAddresses["future_chain"] == "xyz")
    }

    @MainActor @Test func clearingATypedAddressDropsItsKeyEntirely() async {
        let contact = ChatContact(
            publicKey: peerKey,
            name: "Ada",
            walletAddresses: [ChatContact.AddrType.solana: "SolanaAddr"]
        )
        var state = ChatContactForm.State(existing: contact)
        state.solanaAddress = "   "

        #expect(state.walletAddresses[ChatContact.AddrType.solana] == nil)
    }

    // MARK: - Per-field scan routing

    @MainActor @Test func scanResultLandsInTheFieldThatRequestedIt() async {
        let store = TestStore(initialState: ChatContactForm.State()) {
            ChatContactForm()
        }
        store.exhaustivity = .off

        await store.send(.scanTapped(.evm))
        #expect(store.state.scan != nil)
        #expect(store.state.scanTarget == .evm)

        await store.send(.scan(.presented(.foundString("0xScanned"))))

        #expect(store.state.evmAddress == "0xScanned")
        #expect(store.state.transparentAddress.isEmpty)
        #expect(store.state.address.isEmpty)
        #expect(store.state.showsAdditionalAddresses)
        #expect(store.state.scan == nil)
        #expect(store.state.scanTarget == nil)
    }

    @MainActor @Test func scanningTheKeySanitizesItLikeAPaste() async {
        let store = TestStore(initialState: ChatContactForm.State()) {
            ChatContactForm()
        }
        store.exhaustivity = .off

        await store.send(.scanTapped(.publicKey))
        await store.send(.scan(.presented(.foundString("0x\(peerKey.uppercased())"))))

        #expect(store.state.publicKey == peerKey)
        #expect(store.state.isValidKey)
    }

    /// A form opened from a conversation must not let the key be retargeted at someone else.
    @MainActor @Test func aLockedKeyIgnoresBothTypingAndScanning() async {
        let prefill = ChatContact(publicKey: peerKey, name: "Peer", isSaved: false)
        let store = TestStore(initialState: ChatContactForm.State(prefill: prefill)) {
            ChatContactForm()
        }
        store.exhaustivity = .off

        #expect(store.state.isKeyLocked)

        await store.send(.publicKeyChanged(String(repeating: "b", count: 64)))
        await store.send(.scanTapped(.publicKey))

        #expect(store.state.publicKey == peerKey)
        #expect(store.state.scan == nil)
    }

    // MARK: - Block confirmation

    @MainActor @Test func blockAsksBeforeItWrites() async {
        let prefill = ChatContact(publicKey: peerKey, name: "Peer", isSaved: false)
        let store = TestStore(initialState: ChatContactForm.State(prefill: prefill)) {
            ChatContactForm()
        }
        store.exhaustivity = .off

        #expect(store.state.canBlock)

        await store.send(.blockTapped)

        #expect(store.state.alert != nil)
    }

    /// Only a persisted row can be deleted; a peer that was never saved has nothing to remove.
    @MainActor @Test func anUnsavedPeerOffersBlockButNotDelete() async {
        let prefill = ChatContact(publicKey: peerKey, name: "Peer", isSaved: false)
        let state = ChatContactForm.State(prefill: prefill)

        #expect(state.canBlock)
        #expect(!state.isEditing)
    }
}

@Suite(.serialized) struct NewChatScanParityTests {
    private let peerKey = String(repeating: "c", count: 64)

    @MainActor @Test func scanningAPublicKeyFillsTheSearchField() async {
        let store = TestStore(initialState: NewChat.State()) {
            NewChat()
        }
        store.exhaustivity = .off

        await store.send(.scanTapped)
        #expect(store.state.scan != nil)
        #expect(store.state.scan?.checkers == [.publicKeyScanChecker])

        await store.send(.scan(.presented(.foundString(peerKey))))
        await store.receive(\.peerKeyChanged)

        #expect(store.state.scan == nil)
        #expect(store.state.searchInput == peerKey)
        #expect(store.state.isValidKey)
    }

    /// The checker is the guard: a wallet address scanned into the key field is rejected outright
    /// rather than pasted in and failing validation later.
    @Test func publicKeyCheckerAcceptsOnlyIdentityKeys() {
        let checker = PublicKeyScanChecker()

        #expect(checker.checkQRCode("u1someunifiedaddress") == nil)
        #expect(checker.checkQRCode("") == nil)
        #expect(checker.checkQRCode(peerKey) == .foundString(peerKey))
        #expect(checker.checkQRCode("0x\(peerKey.uppercased())") == .foundString(peerKey))
    }
}

// MARK: - Profile: wallet-address surface

@Suite(.serialized) struct ChatProfileSurfaceParityTests {
    @MainActor @Test func theP2pKeyRowIsScopedToTheWalletTabLikeAndroid() async {
        let store = TestStore(initialState: ChatProfile.State()) {
            ChatProfile()
        }
        store.exhaustivity = .off

        // The seed backs up both identities, so it is offered on either tab.
        #expect(!store.state.showsP2PKeyRow)

        await store.send(.tabSelected(.walletAddress))
        #expect(store.state.showsP2PKeyRow)

        await store.send(.tabSelected(.messagingID))
        #expect(!store.state.showsP2PKeyRow)
    }

    @MainActor @Test func switchingWalletSubTabResetsTheCopiedTick() async {
        var initial = ChatProfile.State()
        initial.didCopyAddress = true

        let store = TestStore(initialState: initial) { ChatProfile() }
        store.exhaustivity = .off

        await store.send(.walletSubTabSelected(.transparent))

        #expect(store.state.walletSubTab == .transparent)
        #expect(!store.state.didCopyAddress)
    }

    @MainActor @Test func deleteIdentityConfirmsBeforeHandingUpToRoot() async {
        let store = TestStore(initialState: ChatProfile.State()) {
            ChatProfile()
        }
        store.exhaustivity = .off

        await store.send(.deleteIdentityTapped)
        #expect(store.state.alert != nil)

        // Root turns this into the same full reset the Settings path runs.
        await store.send(.alert(.presented(.deleteIdentityConfirmed)))
        #expect(store.state.alert == nil)
    }
}

// MARK: - Profile: secret reveals (Phase 8 item 6)

/// These are the security assertions for the branch's highest-stakes surface. Each one exists
/// because its failure mode is silent: a secret read before the gate, a secret left in memory
/// after backgrounding, or a secret copied to a pasteboard Android never copies to.
@Suite(.serialized) struct ChatProfileSecretRevealTests {
    private static let phrase = (1...24).map { "word\($0)" }.joined(separator: " ")

    private func storedWallet() -> StoredWallet {
        StoredWallet(
            language: .english,
            seedPhrase: SeedPhrase(Self.phrase),
            version: 1,
            hasUserPassedPhraseBackupTest: true
        )
    }

    /// A one-shot suspension point, so a dependency can be held mid-flight while the test
    /// sends the action that used to cancel it.
    private final class Gate: @unchecked Sendable {
        private let stream: AsyncStream<Void>
        private let continuation: AsyncStream<Void>.Continuation

        init() {
            (stream, continuation) = AsyncStream<Void>.makeStream()
        }

        func wait() async {
            for await _ in stream { break }
        }

        func open() {
            continuation.finish()
        }
    }

    /// Records whether the keychain was touched at all, so "the gate held" can be asserted
    /// directly rather than inferred from empty state.
    private final class ExportSpy: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        var invocations: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }

        func record() {
            lock.lock()
            count += 1
            lock.unlock()
        }
    }

    // MARK: No lock configured

    @MainActor @Test func withNoAppLockTheSeedRevealsStraightAway() async {
        let store = TestStore(initialState: ChatProfile.State()) {
            ChatProfile()
        } withDependencies: {
            $0.appSecurity.authenticationMethod = { .none }
            $0.walletStorage.exportWallet = { self.storedWallet() }
        }
        store.exhaustivity = .off

        await store.send(.seedPhraseTapped)
        await store.receive(\.secretUnlocked)
        await store.receive(\.seedLoaded)

        #expect(store.state.seedWords.count == 24)
        #expect(store.state.seedWords.first?.data == "word1")
        #expect(store.state.showsSeedDialog)
    }

    // MARK: Biometric gate

    @MainActor @Test func aCancelledBiometricPromptNeverReadsTheSeed() async {
        let spy = ExportSpy()
        let store = TestStore(initialState: ChatProfile.State()) {
            ChatProfile()
        } withDependencies: {
            $0.appSecurity.authenticationMethod = { .biometric }
            $0.localAuthentication.authenticateAppLock = { false }
            $0.walletStorage.exportWallet = {
                spy.record()
                return self.storedWallet()
            }
        }
        store.exhaustivity = .off

        await store.send(.seedPhraseTapped)
        await store.receive(\.biometricFinished)

        #expect(spy.invocations == 0)
        #expect(store.state.seedWords.isEmpty)
        #expect(!store.state.showsSeedDialog)
        #expect(store.state.pendingSecret == nil)
    }

    @MainActor @Test func aPassedBiometricPromptRevealsTheSeed() async {
        let store = TestStore(initialState: ChatProfile.State()) {
            ChatProfile()
        } withDependencies: {
            $0.appSecurity.authenticationMethod = { .biometric }
            $0.localAuthentication.authenticateAppLock = { true }
            $0.walletStorage.exportWallet = { self.storedWallet() }
        }
        store.exhaustivity = .off

        await store.send(.seedPhraseTapped)
        await store.receive(\.biometricFinished)
        await store.receive(\.secretUnlocked)
        await store.receive(\.seedLoaded)

        #expect(store.state.seedWords.count == 24)
    }

    /// iOS puts the Face ID / Touch ID sheet up in another process, so the app resigns active
    /// while it is showing — the same notification that hides secrets. The gate has to survive
    /// its own prompt, or every biometric user taps Reveal, authenticates, and sees nothing.
    @MainActor @Test func theBiometricSheetResigningTheAppDoesNotCancelItsOwnReveal() async {
        // Holds the prompt open so the resign-active notification lands while it is genuinely
        // in flight, which is the whole point of the test.
        let prompt = Gate()

        let store = TestStore(initialState: ChatProfile.State()) {
            ChatProfile()
        } withDependencies: {
            $0.appSecurity.authenticationMethod = { .biometric }
            $0.localAuthentication.authenticateAppLock = {
                await prompt.wait()
                return true
            }
            $0.walletStorage.exportWallet = { self.storedWallet() }
        }
        store.exhaustivity = .off

        await store.send(.seedPhraseTapped)
        #expect(store.state.isAwaitingBiometric)

        // What `willResignActive` fires while the system sheet is up.
        await store.send(.hideSensitiveContent)
        #expect(store.state.pendingSecret == .seedPhrase)

        prompt.open()

        await store.receive(\.biometricFinished)
        await store.receive(\.secretUnlocked)
        await store.receive(\.seedLoaded)

        #expect(store.state.seedWords.count == 24)
        #expect(!store.state.isAwaitingBiometric)
    }

    /// The reprieve above lasts exactly as long as the prompt. Once it resolves, a real
    /// backgrounding clears the gate again.
    @MainActor @Test func onceTheBiometricPromptResolvesBackgroundingClearsTheGateAgain() async {
        let store = TestStore(initialState: ChatProfile.State()) {
            ChatProfile()
        } withDependencies: {
            $0.appSecurity.authenticationMethod = { .biometric }
            $0.localAuthentication.authenticateAppLock = { false }
            $0.walletStorage.exportWallet = { self.storedWallet() }
        }
        store.exhaustivity = .off

        await store.send(.seedPhraseTapped)
        await store.receive(\.biometricFinished)

        #expect(!store.state.isAwaitingBiometric)
        #expect(store.state.pendingSecret == nil)

        var pinned = store.state
        pinned.pendingSecret = .seedPhrase
        pinned.pinEntry = ChatProfile.State.PINEntry(pin: "12")

        let second = TestStore(initialState: pinned) { ChatProfile() }
        second.exhaustivity = .off

        await second.send(.hideSensitiveContent)

        #expect(second.state.pendingSecret == nil)
        #expect(second.state.pinEntry == nil)
    }

    // MARK: PIN gate

    @MainActor @Test func aPinLockOpensTheKeypadWithoutReadingAnything() async {
        let spy = ExportSpy()
        let store = TestStore(initialState: ChatProfile.State()) {
            ChatProfile()
        } withDependencies: {
            $0.date.now = { Date(timeIntervalSince1970: 0) }
            $0.appSecurity.authenticationMethod = { .pin }
            $0.appSecurity.lockoutRemaining = { _ in 0 }
            $0.walletStorage.exportWallet = {
                spy.record()
                return self.storedWallet()
            }
        }
        store.exhaustivity = .off

        await store.send(.seedPhraseTapped)

        #expect(store.state.pinEntry != nil)
        #expect(store.state.pendingSecret == .seedPhrase)
        #expect(spy.invocations == 0)
        #expect(store.state.seedWords.isEmpty)
    }

    @MainActor @Test func awrongPinKeepsTheSeedSealed() async {
        let spy = ExportSpy()
        let store = TestStore(initialState: ChatProfile.State()) {
            ChatProfile()
        } withDependencies: {
            $0.date.now = { Date(timeIntervalSince1970: 0) }
            $0.appSecurity.authenticationMethod = { .pin }
            $0.appSecurity.lockoutRemaining = { _ in 0 }
            $0.appSecurity.verifyPIN = { _, _ in .incorrect }
            $0.walletStorage.exportWallet = {
                spy.record()
                return self.storedWallet()
            }
        }
        store.exhaustivity = .off

        await store.send(.seedPhraseTapped)
        for _ in 0..<6 {
            await store.send(.pinKeyTapped(.digit(1)))
        }
        await store.receive(\.pinVerificationFinished)

        #expect(spy.invocations == 0)
        #expect(store.state.seedWords.isEmpty)
        #expect(store.state.pinEntry?.errorMessage != nil)
    }

    @MainActor @Test func theCorrectPinRevealsTheSeedAndClosesTheKeypad() async {
        let store = TestStore(initialState: ChatProfile.State()) {
            ChatProfile()
        } withDependencies: {
            $0.date.now = { Date(timeIntervalSince1970: 0) }
            $0.appSecurity.authenticationMethod = { .pin }
            $0.appSecurity.lockoutRemaining = { _ in 0 }
            $0.appSecurity.verifyPIN = { _, _ in .success }
            $0.walletStorage.exportWallet = { self.storedWallet() }
        }
        store.exhaustivity = .off

        await store.send(.seedPhraseTapped)
        for _ in 0..<6 {
            await store.send(.pinKeyTapped(.digit(1)))
        }
        await store.receive(\.pinVerificationFinished)
        await store.receive(\.secretUnlocked)
        await store.receive(\.seedLoaded)

        #expect(store.state.pinEntry == nil)
        #expect(store.state.seedWords.count == 24)
    }

    @MainActor @Test func cancellingTheKeypadDropsThePendingReveal() async {
        let store = TestStore(initialState: ChatProfile.State()) {
            ChatProfile()
        } withDependencies: {
            $0.date.now = { Date(timeIntervalSince1970: 0) }
            $0.appSecurity.authenticationMethod = { .pin }
            $0.appSecurity.lockoutRemaining = { _ in 0 }
        }
        store.exhaustivity = .off

        await store.send(.seedPhraseTapped)
        await store.send(.pinCancelled)

        #expect(store.state.pinEntry == nil)
        #expect(store.state.pendingSecret == nil)
        #expect(store.state.seedWords.isEmpty)
    }

    // MARK: P2P wallet key

    @MainActor @Test func theP2pKeyComesFromTheOfframpExportBehindTheSameGate() async {
        let key = OfframpWalletKey(address: "0xOwner", privateKeyHex: RedactableString("0xsecret"))
        let store = TestStore(initialState: ChatProfile.State()) {
            ChatProfile()
        } withDependencies: {
            $0.appSecurity.authenticationMethod = { .none }
            $0.offramp.exportWalletKey = { key }
        }
        store.exhaustivity = .off

        await store.send(.p2pKeyTapped)
        await store.receive(\.secretUnlocked)
        await store.receive(\.p2pKeyLoaded)

        #expect(store.state.p2pKey == key)
        #expect(store.state.showsP2PKeyDialog)
    }

    @MainActor @Test func aFailedExportSurfacesAnErrorRatherThanAnEmptyDialog() async {
        struct Boom: Error { }

        let store = TestStore(initialState: ChatProfile.State()) {
            ChatProfile()
        } withDependencies: {
            $0.appSecurity.authenticationMethod = { .none }
            $0.offramp.exportWalletKey = { throw Boom() }
        }
        store.exhaustivity = .off

        await store.send(.p2pKeyTapped)
        await store.receive(\.secretUnlocked)
        await store.receive(\.secretLoadFailed)

        #expect(store.state.p2pKey == nil)
        #expect(store.state.secretFailed)
    }

    // MARK: Hide on backgrounding

    /// `hideSensitiveContent` is what `willResignActive`, `didEnterBackground`, a screen
    /// recording starting, and `onDisappear` all send. If this leaves anything behind, the
    /// app-switcher snapshot keeps a recovery phrase in it.
    @MainActor @Test func backgroundingClearsEverySecretAndItsGate() async {
        let key = OfframpWalletKey(address: "0xOwner", privateKeyHex: RedactableString("0xsecret"))
        var initial = ChatProfile.State()
        initial.seedWords = [RedactableString("word1")]
        initial.p2pKey = key
        initial.pendingSecret = .p2pKey
        initial.pinEntry = ChatProfile.State.PINEntry(pin: "12")
        initial.didCopyP2PKey = true
        initial.didCopyP2PAddress = true
        initial.secretFailed = true

        let store = TestStore(initialState: initial) { ChatProfile() }
        store.exhaustivity = .off

        await store.send(.hideSensitiveContent)

        #expect(store.state.seedWords.isEmpty)
        #expect(store.state.p2pKey == nil)
        #expect(store.state.pendingSecret == nil)
        #expect(store.state.pinEntry == nil)
        #expect(!store.state.didCopyP2PKey)
        #expect(!store.state.didCopyP2PAddress)
        #expect(!store.state.secretFailed)
        #expect(!store.state.isShowingSecret)
    }

    @MainActor @Test func leavingTheScreenAlsoDropsTheSecrets() async {
        var initial = ChatProfile.State()
        initial.seedWords = [RedactableString("word1")]

        let store = TestStore(initialState: initial) { ChatProfile() }
        store.exhaustivity = .off

        await store.send(.onDisappear)
        await store.receive(\.hideSensitiveContent)

        #expect(store.state.seedWords.isEmpty)
    }

    // MARK: Pasteboard scope

    /// Android's seed dialog has no copy button; only the P2P dialog offers one, for both of
    /// its fields. Revealing the seed must therefore never touch the pasteboard.
    @MainActor @Test func revealingTheSeedNeverTouchesThePasteboard() async {
        let spy = ExportSpy()
        let store = TestStore(initialState: ChatProfile.State()) {
            ChatProfile()
        } withDependencies: {
            $0.appSecurity.authenticationMethod = { .none }
            $0.walletStorage.exportWallet = { self.storedWallet() }
            $0.pasteboard.setString = { _ in spy.record() }
        }
        store.exhaustivity = .off

        await store.send(.seedPhraseTapped)
        await store.receive(\.secretUnlocked)
        await store.receive(\.seedLoaded)

        #expect(store.state.seedWords.count == 24)
        #expect(spy.invocations == 0)
    }

    @MainActor @Test func theP2pDialogCopiesBothOfItsFields() async {
        let key = OfframpWalletKey(address: "0xOwner", privateKeyHex: RedactableString("0xsecret"))
        var initial = ChatProfile.State()
        initial.p2pKey = key

        let copied = LockIsolated<[String]>([])
        let store = TestStore(initialState: initial) {
            ChatProfile()
        } withDependencies: {
            $0.mainQueue = DispatchQueue.test.eraseToAnyScheduler()
            $0.pasteboard.setString = { value in copied.withValue { $0.append(value.data) } }
        }
        store.exhaustivity = .off

        await store.send(.copyP2PAddressTapped)
        #expect(store.state.didCopyP2PAddress)

        await store.send(.copyP2PKeyTapped)
        #expect(store.state.didCopyP2PKey)
        #expect(!store.state.didCopyP2PAddress)

        #expect(copied.value == ["0xOwner", "0xsecret"])
    }
}
