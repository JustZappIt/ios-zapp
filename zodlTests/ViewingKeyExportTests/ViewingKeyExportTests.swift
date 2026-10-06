//
//  ViewingKeyExportTests.swift
//  zodlTests
//
//  Export viewing key (Android's `ViewingKeyExportVM`). What matters: nothing is read from the SDK
//  until the app lock says yes, a cancelled or failed prompt keeps the key hidden, the key is the
//  chosen account's and the chosen level's, and it leaves state the moment the screen hides.
//

import ComposableArchitecture
import Foundation
import Testing
@testable @preconcurrency import ZcashLightClientKit
@testable import zodl_internal

/// Serialized: the screen reads the process-wide selected-account shared store.
@Suite(.serialized) struct ViewingKeyExportTests {
    private static let zappUFVK = "uviewtest1zappfullviewingkey"
    private static let zappUIVK = "uivktest1zappincomingviewingkey"
    private static let keystoneUFVK = "uviewtest1keystonefullviewingkey"

    private static func walletAccount(
        idByte: UInt8,
        keystone: Bool = false,
        ufvk: String?,
        uivk: String?
    ) -> WalletAccount {
        WalletAccount(
            Account(
                id: AccountUUID(id: [UInt8](repeating: idByte, count: 16)),
                name: keystone ? "Keystone" : "Zapp",
                keySource: keystone ? String(localizable: .accountsKeystone).lowercased() : nil,
                seedFingerprint: nil,
                hdAccountIndex: Zip32AccountIndex(keystone ? 1 : 0),
                ufvk: ufvk.map { UnifiedFullViewingKey(validatedEncoding: $0) },
                uivk: uivk.map { UnifiedIncomingViewingKey(validatedEncoding: $0) }
            )
        )
    }

    private static let zapp = walletAccount(idByte: 1, ufvk: zappUFVK, uivk: zappUIVK)
    private static let keystone = walletAccount(idByte: 2, keystone: true, ufvk: keystoneUFVK, uivk: nil)

    /// Counts SDK account listings, so "the gate held" is asserted directly: the load on appear is
    /// one call, and every reveal that gets past the gate is one more.
    private final class ListingSpy: @unchecked Sendable {
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

    @MainActor private func makeStore(
        selected: WalletAccount? = ViewingKeyExportTests.zapp,
        accounts: [WalletAccount] = [ViewingKeyExportTests.zapp, ViewingKeyExportTests.keystone],
        spy: ListingSpy = ListingSpy(),
        configure: @escaping (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<ViewingKeyExport> {
        var state = ViewingKeyExport.State()
        state.$selectedWalletAccount.withLock { $0 = selected }
        let store = TestStore(initialState: state) {
            ViewingKeyExport()
        } withDependencies: {
            $0.sdkSynchronizer.walletAccounts = {
                spy.record()
                return accounts
            }
            $0.screenCapture.isCaptured = { false }
            $0.date.now = { Date(timeIntervalSince1970: 0) }
            configure(&$0)
        }
        store.exhaustivity = .off

        return store
    }

    @MainActor private func loadAndAcknowledge(_ store: TestStoreOf<ViewingKeyExport>) async {
        await store.send(.onAppear)
        await store.receive(\.accountsLoaded)
        await store.send(.acknowledgementToggled)
    }

    // MARK: - Loading

    @MainActor @Test func theSelectedAccountIsPreselectedWithItsFullKey() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let store = makeStore(selected: Self.keystone)

            await store.send(.onAppear)
            await store.receive(\.accountsLoaded)

            #expect(store.state.isLoading == false)
            #expect(store.state.accounts.map(\.id) == [Self.zapp.id, Self.keystone.id])
            #expect(store.state.selectedAccountId == Self.keystone.id)
            #expect(store.state.selectedKeyType == .ufvk)
            #expect(store.state.accounts.last?.availableKeyTypes == [.ufvk])
            #expect(store.state.accounts.last?.accountIndex == 1)
        }
    }

    @MainActor @Test func anAccountWithOnlyAnIncomingKeyPreselectsIt() async {
        let incomingOnly = Self.walletAccount(idByte: 3, ufvk: nil, uivk: Self.zappUIVK)

        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let store = makeStore(selected: incomingOnly, accounts: [incomingOnly])

            await store.send(.onAppear)
            await store.receive(\.accountsLoaded)

            #expect(store.state.selectedKeyType == .uivk)
            #expect(store.state.isSelectedKeyAvailable)
        }
    }

    @MainActor @Test func aFailedListingSurfacesTheLoadError() async {
        struct Boom: Error { }

        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let store = TestStore(initialState: ViewingKeyExport.State()) {
                ViewingKeyExport()
            } withDependencies: {
                $0.sdkSynchronizer.walletAccounts = { throw Boom() }
            }
            store.exhaustivity = .off

            await store.send(.onAppear)
            await store.receive(\.accountsLoadFailed)

            #expect(store.state.isLoading == false)
            #expect(store.state.error == .loadFailed)
            #expect(store.state.canReveal == false)
        }
    }

    // MARK: - The gate

    @MainActor @Test func revealIsRefusedUntilTheExportIsAcknowledged() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let spy = ListingSpy()
            let store = makeStore(spy: spy) {
                $0.appSecurity.authenticationMethod = { .none }
            }

            await store.send(.onAppear)
            await store.receive(\.accountsLoaded)
            await store.send(.revealTapped)

            #expect(store.state.authGate.isAuthenticating == false)
            #expect(store.state.revealedKey == nil)
            #expect(spy.invocations == 1)
        }
    }

    /// Android's `REQUIRE_AUTHENTICATION`: no app lock is not a free pass. iOS asks the device owner.
    @MainActor @Test func withNoAppLockTheDeviceOwnerMustStillAuthenticate() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let spy = ListingSpy()
            let store = makeStore(spy: spy) {
                $0.appSecurity.authenticationMethod = { .none }
                $0.localAuthentication.authenticateAppLock = { false }
            }

            await loadAndAcknowledge(store)
            await store.send(.revealTapped)
            await store.receive(\.authGate.biometricFinished)
            await store.receive(\.authGate.delegate.failed)

            #expect(spy.invocations == 1)
            #expect(store.state.revealedKey == nil)
            #expect(store.state.error == .authenticationFailed)
            #expect(store.state.isAuthenticating == false)
        }
    }

    @MainActor @Test func aPassedPromptRevealsTheSelectedAccountsFullKey() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let spy = ListingSpy()
            let store = makeStore(selected: Self.keystone, spy: spy) {
                $0.appSecurity.authenticationMethod = { .biometric }
                $0.localAuthentication.authenticateAppLock = { true }
            }

            await loadAndAcknowledge(store)
            await store.send(.revealTapped)
            await store.receive(\.authGate.delegate.authenticated)
            await store.receive(\.keyLoaded)

            #expect(spy.invocations == 2)
            #expect(store.state.revealedKey?.keyType == .ufvk)
            #expect(store.state.revealedKey?.encodedKey.data == Self.keystoneUFVK)
            #expect(store.state.error == nil)
            #expect(store.state.isSelectionEnabled == false)
        }
    }

    @MainActor @Test func choosingTheIncomingLevelRevealsTheIncomingKey() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let store = makeStore {
                $0.appSecurity.authenticationMethod = { .biometric }
                $0.localAuthentication.authenticateAppLock = { true }
            }

            await store.send(.onAppear)
            await store.receive(\.accountsLoaded)
            await store.send(.acknowledgementToggled)
            // Changing the level withdraws the acknowledgement, as on Android.
            await store.send(.keyTypeSelected(.uivk))
            #expect(store.state.isAcknowledged == false)

            await store.send(.acknowledgementToggled)
            await store.send(.revealTapped)
            await store.receive(\.keyLoaded)

            #expect(store.state.revealedKey?.keyType == .uivk)
            #expect(store.state.revealedKey?.encodedKey.data == Self.zappUIVK)
        }
    }

    @MainActor @Test func anUnavailableLevelCannotBeChosen() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let store = makeStore(selected: Self.keystone)

            await store.send(.onAppear)
            await store.receive(\.accountsLoaded)
            await store.send(.keyTypeSelected(.uivk))

            #expect(store.state.selectedKeyType == .ufvk)
        }
    }

    @MainActor @Test func cancellingThePinPadKeepsTheKeyHidden() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let spy = ListingSpy()
            let store = makeStore(spy: spy) {
                $0.appSecurity.authenticationMethod = { .pin }
                $0.appSecurity.lockoutRemaining = { _ in 0 }
            }

            await loadAndAcknowledge(store)
            await store.send(.revealTapped)
            await store.receive(\.authGate.start)
            #expect(store.state.authGate.pinEntry != nil)
            #expect(store.state.canReveal == false)

            await store.send(.authGate(.pinCancelled))
            await store.receive(\.authGate.delegate.failed)

            #expect(store.state.authGate.pinEntry == nil)
            #expect(store.state.error == .authenticationFailed)
            #expect(store.state.revealedKey == nil)
            #expect(spy.invocations == 1)
        }
    }

    @MainActor @Test func aWrongPinKeepsTheKeySealedAndTheRightOneRevealsIt() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let pins = LockIsolated<[String]>([])
            let store = makeStore {
                $0.appSecurity.authenticationMethod = { .pin }
                $0.appSecurity.lockoutRemaining = { _ in 0 }
                $0.appSecurity.verifyPIN = { pin, _ in
                    pins.withValue { $0.append(pin) }
                    return pin == "123456" ? .success : .incorrect
                }
            }

            await loadAndAcknowledge(store)
            await store.send(.revealTapped)
            for _ in 0..<6 {
                await store.send(.authGate(.pinKeyTapped(.digit(9))))
            }
            await store.receive(\.authGate.pinVerificationFinished)
            #expect(store.state.revealedKey == nil)
            #expect(store.state.authGate.pinEntry?.errorMessage != nil)

            for digit in 1...6 {
                await store.send(.authGate(.pinKeyTapped(.digit(digit))))
            }
            await store.receive(\.authGate.delegate.authenticated)
            await store.receive(\.keyLoaded)

            #expect(pins.value == ["999999", "123456"])
            #expect(store.state.authGate.pinEntry == nil)
            #expect(store.state.revealedKey?.encodedKey.data == Self.zappUFVK)
        }
    }

    @MainActor @Test func aRunningRecordingRefusesBeforeAuthenticating() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let prompts = LockIsolated(0)
            let store = makeStore {
                $0.screenCapture.isCaptured = { true }
                $0.appSecurity.authenticationMethod = { .biometric }
                $0.localAuthentication.authenticateAppLock = {
                    prompts.withValue { $0 += 1 }
                    return true
                }
            }

            await loadAndAcknowledge(store)
            await store.send(.revealTapped)

            #expect(store.state.error == .screenRecording)
            #expect(prompts.value == 0)
            #expect(store.state.revealedKey == nil)
        }
    }

    /// The account disappeared between the listing and the reveal: an error, never an empty card.
    @MainActor @Test func aKeyThatIsGoneByRevealTimeReportsUnavailable() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let listings = LockIsolated(0)
            let store = makeStore {
                $0.appSecurity.authenticationMethod = { .none }
                $0.localAuthentication.authenticateAppLock = { true }
                $0.sdkSynchronizer.walletAccounts = {
                    listings.withValue { $0 += 1 }
                    return listings.value == 1 ? [Self.zapp] : []
                }
            }

            await loadAndAcknowledge(store)
            await store.send(.revealTapped)
            await store.receive(\.keyLoaded)

            #expect(store.state.revealedKey == nil)
            #expect(store.state.error == .keyUnavailable)
        }
    }

    // MARK: - After the reveal

    @MainActor @Test func copyingWritesTheExactKey() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let copied = LockIsolated<String?>(nil)
            let store = makeStore {
                $0.appSecurity.authenticationMethod = { .biometric }
                $0.localAuthentication.authenticateAppLock = { true }
                $0.pasteboard.setString = { value in copied.setValue(value.data) }
                $0.mainQueue = .immediate
            }

            await loadAndAcknowledge(store)
            await store.send(.revealTapped)
            await store.receive(\.keyLoaded)
            await store.send(.copyTapped)

            #expect(copied.value == Self.zappUFVK)
            #expect(store.state.isCopied)
        }
    }

    @MainActor @Test func backgroundingDropsTheKeyAndTheShareSheet() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let store = makeStore {
                $0.appSecurity.authenticationMethod = { .biometric }
                $0.localAuthentication.authenticateAppLock = { true }
            }

            await loadAndAcknowledge(store)
            await store.send(.revealTapped)
            await store.receive(\.keyLoaded)
            await store.send(.shareTapped)
            #expect(store.state.sharedKey?.data == Self.zappUFVK)

            await store.send(.hideSensitiveContent)

            #expect(store.state.revealedKey == nil)
            #expect(store.state.sharedKey == nil)
            #expect(store.state.isSelectionEnabled)
            // Hiding keeps the choices but not the key: revealing again goes back through the gate.
            #expect(store.state.isAcknowledged)
            #expect(store.state.canReveal)
        }
    }

    @MainActor @Test func switchingAccountWithdrawsTheAcknowledgement() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let store = makeStore()

            await loadAndAcknowledge(store)
            await store.send(.accountSelected(Self.keystone.id))

            #expect(store.state.selectedAccountId == Self.keystone.id)
            #expect(store.state.isAcknowledged == false)
            #expect(store.state.canReveal == false)
        }
    }
}
