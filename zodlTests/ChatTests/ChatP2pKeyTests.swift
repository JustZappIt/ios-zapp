//
//  ChatP2pKeyTests.swift
//  zodlTests
//
//  The P2P wallet key screen (Android's `ChatP2pKeyVM`): the smart-account address shows without
//  a prompt, the owner key only after the app lock, and the key never outlives the app being
//  frontmost. Plus the profile entry point, which now pushes this screen instead of a dialog.
//

import ComposableArchitecture
import Foundation
import Testing
@testable import zodl_internal

@Suite(.serialized) struct ChatP2pKeyTests {
    private static let smartAccount = "0x5Ma7Acc0un7000000000000000000000000000001"
    private static let key = OfframpWalletKey(
        address: "0x0wnerAddre55000000000000000000000000000002",
        privateKeyHex: RedactableString("0xprivatekeyhex")
    )

    @MainActor private func makeStore(
        configure: @escaping (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<ChatP2pKey> {
        let store = TestStore(initialState: ChatP2pKey.State()) {
            ChatP2pKey()
        } withDependencies: {
            $0.offramp.accountAddress = { Self.smartAccount }
            $0.screenCapture.isCaptured = { false }
            $0.date.now = { Date(timeIntervalSince1970: 0) }
            configure(&$0)
        }
        store.exhaustivity = .off

        return store
    }

    // MARK: - Smart account

    @MainActor @Test func theSmartAccountShowsWithoutAuthenticating() async {
        let store = makeStore()

        await store.send(.onAppear)
        await store.receive(\.smartAccountLoaded)

        #expect(store.state.smartAccountAddress == Self.smartAccount)
        #expect(store.state.ownerKey == nil)
        #expect(store.state.authGate.isAuthenticating == false)
    }

    /// A Keystone selection has no smart account (`unsupportedAccount`): the card is simply absent.
    @MainActor @Test func anUnavailableSmartAccountDropsTheCard() async {
        let store = makeStore {
            $0.offramp.accountAddress = { throw OfframpClientError.unsupportedAccount }
        }

        await store.send(.onAppear)
        await store.receive(\.smartAccountLoaded)

        #expect(store.state.smartAccountAddress == nil)
        #expect(store.state.keyFailed == false)
    }

    // MARK: - Owner key gate

    @MainActor @Test func withNoAppLockTheOwnerKeyRevealsStraightAway() async {
        let store = makeStore {
            $0.appSecurity.authenticationMethod = { .none }
            $0.offramp.exportWalletKey = { Self.key }
        }

        await store.send(.revealTapped)
        await store.receive(\.ownerKeyLoaded)

        #expect(store.state.ownerKey == Self.key)
    }

    @MainActor @Test func aCancelledBiometricPromptNeverExportsTheKey() async {
        let exports = LockIsolated(0)
        let store = makeStore {
            $0.appSecurity.authenticationMethod = { .biometric }
            $0.localAuthentication.authenticateAppLock = { false }
            $0.offramp.exportWalletKey = {
                exports.withValue { $0 += 1 }
                return Self.key
            }
        }

        await store.send(.revealTapped)
        await store.receive(\.authGate.delegate.failed)

        #expect(exports.value == 0)
        #expect(store.state.ownerKey == nil)
        // Silent, as on Android: a dismissed prompt is not an error.
        #expect(store.state.keyFailed == false)
        #expect(store.state.isRevealing == false)
    }

    @MainActor @Test func theCorrectPinRevealsTheOwnerKey() async {
        let store = makeStore {
            $0.appSecurity.authenticationMethod = { .pin }
            $0.appSecurity.lockoutRemaining = { _ in 0 }
            $0.appSecurity.verifyPIN = { _, _ in .success }
            $0.offramp.exportWalletKey = { Self.key }
        }

        await store.send(.revealTapped)
        await store.receive(\.authGate.start)
        #expect(store.state.authGate.pinEntry != nil)
        #expect(store.state.ownerKey == nil)

        for digit in 1...6 {
            await store.send(.authGate(.pinKeyTapped(.digit(digit))))
        }
        await store.receive(\.ownerKeyLoaded)

        #expect(store.state.authGate.pinEntry == nil)
        #expect(store.state.ownerKey == Self.key)
    }

    @MainActor @Test func aRunningRecordingRefusesTheReveal() async {
        let prompts = LockIsolated(0)
        let store = makeStore {
            $0.screenCapture.isCaptured = { true }
            $0.appSecurity.authenticationMethod = { .biometric }
            $0.localAuthentication.authenticateAppLock = {
                prompts.withValue { $0 += 1 }
                return true
            }
        }

        await store.send(.revealTapped)

        #expect(store.state.keyBlockedByCapture)
        #expect(prompts.value == 0)
        #expect(store.state.ownerKey == nil)
    }

    @MainActor @Test func aFailedExportSurfacesAnError() async {
        struct Boom: Error { }

        let store = makeStore {
            $0.appSecurity.authenticationMethod = { .none }
            $0.offramp.exportWalletKey = { throw Boom() }
        }

        await store.send(.revealTapped)
        await store.receive(\.ownerKeyFailed)

        #expect(store.state.keyFailed)
        #expect(store.state.ownerKey == nil)
    }

    // MARK: - Copy and hide

    @MainActor @Test func copyingThePrivateKeyWritesItAndTicksOnlyThatField() async {
        let copied = LockIsolated<String?>(nil)
        let store = makeStore {
            $0.appSecurity.authenticationMethod = { .none }
            $0.offramp.exportWalletKey = { Self.key }
            $0.pasteboard.setString = { value in copied.setValue(value.data) }
            $0.mainQueue = .immediate
        }

        await store.send(.revealTapped)
        await store.receive(\.ownerKeyLoaded)
        await store.send(.copyTapped(.privateKey))

        #expect(copied.value == Self.key.privateKeyHex.data)
        #expect(store.state.copiedField == .privateKey)
    }

    @MainActor @Test func backgroundingDropsTheOwnerKeyButKeepsTheSmartAccount() async {
        var state = ChatP2pKey.State()
        state.smartAccountAddress = Self.smartAccount
        state.ownerKey = Self.key
        state.copiedField = .privateKey
        let store = TestStore(initialState: state) {
            ChatP2pKey()
        }
        store.exhaustivity = .off

        await store.send(.hideSensitiveContent)

        #expect(store.state.ownerKey == nil)
        #expect(store.state.copiedField == nil)
        #expect(store.state.smartAccountAddress == Self.smartAccount)
    }

    // MARK: - Entry point

    /// The profile row no longer opens the PIN prompt and dialog itself; it hands off to Root.
    @MainActor @Test func theProfileRowNoLongerStartsARevealOfItsOwn() async {
        let store = TestStore(initialState: ChatProfile.State()) {
            ChatProfile()
        }

        await store.send(.p2pKeyScreenTapped)

        #expect(store.state.pendingSecret == nil)
        #expect(store.state.pinEntry == nil)
    }
}
