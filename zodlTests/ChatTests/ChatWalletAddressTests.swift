//
//  ChatWalletAddressTests.swift
//  zodlTests
//
//  The dedicated wallet-address screen. What matters here is that the list is derived, not
//  stored: a missing Base lookup or an unready wallet account must drop its own card and leave
//  the rest, and the copy tick must follow exactly one address.
//

import ComposableArchitecture
import Foundation
import Testing
@testable @preconcurrency import ZcashLightClientKit
@testable import zodl_internal

/// Serialized: the screen reads the process-wide selected-account shared store.
@Suite(.serialized) struct ChatWalletAddressTests {
    private let unifiedAddress = """
        utest1zkkkjfxkamagznjr6ayemffj2d2gacdwpzcyw669pvg06xevzqslpmm27zjsctlkstl2vsw62xrjktmzqcu4yu9zdhdxqz3kafa4j2q85y6mv74rzjcgjg8c0ytrg7d\
        wyzwtgnuc76h
        """

    private let baseAddress = "0xBa5eAcc0un7"

    private func account(idByte: UInt8, keySource: String?, hasAddress: Bool) throws -> WalletAccount {
        var account = WalletAccount(
            Account(
                id: AccountUUID(id: [UInt8](repeating: idByte, count: 16)),
                name: "Zodl",
                keySource: keySource,
                seedFingerprint: nil,
                hdAccountIndex: Zip32AccountIndex(0),
                ufvk: nil,
                uivk: nil
            )
        )
        if hasAddress {
            account.defaultUA = try UnifiedAddress(encoding: unifiedAddress, network: .testnet)
        }

        return account
    }

    private func zashiAccount(hasAddress: Bool = true) throws -> WalletAccount {
        try account(idByte: 0, keySource: nil, hasAddress: hasAddress)
    }

    /// A hardware wallet is a DIFFERENT seed, so its addresses are a different wallet's.
    private func keystoneAccount(hasAddress: Bool = true) throws -> WalletAccount {
        try account(
            idByte: 1,
            keySource: String(localizable: .accountsKeystone).lowercased(),
            hasAddress: hasAddress
        )
    }

    private func state(withAccount: Bool, base: String?) throws -> ChatWalletAddress.State {
        var state = ChatWalletAddress.State()
        state.$selectedWalletAccount.withLock { $0 = withAccount ? try? zashiAccount() : nil }
        state.baseAddress = base

        return state
    }

    // MARK: - Derived list

    @Test func addressesAreListedInAndroidsOrder() throws {
        try withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let items = try state(withAccount: true, base: baseAddress).addresses

            #expect(items.map(\.kind) == [.shielded, .transparent, .base])
            #expect(items.first?.address == unifiedAddress)
            #expect(items.last?.address == baseAddress)
        }
    }

    @Test func onlyTheZcashAddressesOfferAQrCode() throws {
        try withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let items = try state(withAccount: true, base: baseAddress).addresses

            #expect(items.filter(\.hasQRCode).map(\.kind) == [.shielded, .transparent])
        }
    }

    @Test func aFailedBaseLookupLeavesTheZcashAddressesIntact() throws {
        try withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let items = try state(withAccount: true, base: nil).addresses

            #expect(items.map(\.kind) == [.shielded, .transparent])
        }
    }

    @Test func anUnreadyWalletAccountStillShowsTheBaseAddress() throws {
        try withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let items = try state(withAccount: false, base: baseAddress).addresses

            #expect(items.map(\.kind) == [.base])
        }
    }

    @Test func withNothingResolvedTheListIsEmpty() throws {
        try withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let items = try state(withAccount: false, base: nil).addresses

            #expect(items.isEmpty)
        }
    }

    /// The account halves of this screen must agree. `offramp.accountAddress()` resolves against
    /// the SELECTED account, so reading the Zcash addresses off the Zashi one would show a
    /// Keystone user the software wallet's addresses — a different seed, and money sent to an
    /// account they are not looking at.
    @Test func theAddressesFollowTheSelectedAccountNotTheZashiOne() throws {
        try withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = ChatWalletAddress.State()
            @Shared(.inMemory(.zashiWalletAccount)) var zashi: WalletAccount?
            $zashi.withLock { $0 = try? zashiAccount(hasAddress: false) }
            state.$selectedWalletAccount.withLock { $0 = try? keystoneAccount() }

            #expect(state.addresses.first?.address == unifiedAddress)
        }
    }

    @Test func aSelectionWithoutAddressesShowsNoneEvenWhenZashiHasThem() throws {
        try withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = ChatWalletAddress.State()
            @Shared(.inMemory(.zashiWalletAccount)) var zashi: WalletAccount?
            $zashi.withLock { $0 = try? zashiAccount() }
            state.$selectedWalletAccount.withLock { $0 = try? keystoneAccount(hasAddress: false) }

            #expect(state.addresses.isEmpty)
        }
    }

    // MARK: - Base lookup

    @MainActor @Test func aResolvedBaseAddressAddsANonScannableCard() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let store = TestStore(initialState: ChatWalletAddress.State()) {
                ChatWalletAddress()
            } withDependencies: {
                $0.offramp.accountAddress = { self.baseAddress }
            }
            store.exhaustivity = .off

            await store.send(.onAppear)
            await store.receive(\.baseAddressLoaded)

            #expect(store.state.baseAddress == baseAddress)
            #expect(store.state.addresses.map(\.hasQRCode) == [false])
        }
    }

    /// A throwing lookup and an empty string are the same outcome: no card, no error state.
    @MainActor @Test func anUnavailableBaseAddressIsSimplyAbsent() async {
        struct Boom: Error { }

        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let store = TestStore(initialState: ChatWalletAddress.State()) {
                ChatWalletAddress()
            } withDependencies: {
                $0.offramp.accountAddress = { throw Boom() }
            }
            store.exhaustivity = .off

            await store.send(.onAppear)
            await store.receive(\.baseAddressLoaded)
            #expect(store.state.baseAddress == nil)

            await store.send(.baseAddressLoaded(""))
            #expect(store.state.baseAddress == nil)
            #expect(store.state.addresses.isEmpty)
        }
    }

    // MARK: - Copy feedback

    @MainActor @Test func copyingWritesTheExactAddressAndTicksOnlyThatCard() async throws {
        try await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let copied = LockIsolated<[String]>([])
            var initial = ChatWalletAddress.State()
            initial.baseAddress = baseAddress
            let account = try zashiAccount()
            initial.$selectedWalletAccount.withLock { $0 = account }

            let store = TestStore(initialState: initial) {
                ChatWalletAddress()
            } withDependencies: {
                $0.mainQueue = DispatchQueue.test.eraseToAnyScheduler()
                $0.pasteboard.setString = { value in copied.withValue { $0.append(value.data) } }
            }
            store.exhaustivity = .off

            await store.send(.copyAddressTapped(unifiedAddress))
            #expect(copied.value == [unifiedAddress])
            #expect(store.state.copiedAddress == unifiedAddress)

            // A second copy moves the tick rather than lighting both cards.
            await store.send(.copyAddressTapped(baseAddress))
            #expect(copied.value == [unifiedAddress, baseAddress])
            #expect(store.state.copiedAddress == baseAddress)
        }
    }

    @MainActor @Test func theTickClearsWhenItsTimerFires() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let mainQueue = DispatchQueue.test

            let store = TestStore(initialState: ChatWalletAddress.State()) {
                ChatWalletAddress()
            } withDependencies: {
                $0.mainQueue = mainQueue.eraseToAnyScheduler()
                $0.pasteboard.setString = { _ in }
            }
            store.exhaustivity = .off

            await store.send(.copyAddressTapped(baseAddress))
            #expect(store.state.copiedAddress == baseAddress)

            await mainQueue.advance(by: .seconds(2))
            await store.receive(\.copyIndicatorExpired)

            #expect(store.state.copiedAddress == nil)
        }
    }

    /// Leaving the screen must not leave a delayed tick or an in-flight lookup behind it.
    @MainActor @Test func leavingTheScreenCancelsTheDelayedTick() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let mainQueue = DispatchQueue.test

            let store = TestStore(initialState: ChatWalletAddress.State()) {
                ChatWalletAddress()
            } withDependencies: {
                $0.mainQueue = mainQueue.eraseToAnyScheduler()
                $0.pasteboard.setString = { _ in }
            }
            store.exhaustivity = .off

            await store.send(.copyAddressTapped(baseAddress))
            await store.send(.onDisappear)
            await mainQueue.advance(by: .seconds(2))

            #expect(store.state.copiedAddress == baseAddress)
        }
    }

    @MainActor @Test func anEmptyAddressIsNeverCopied() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let copied = LockIsolated<[String]>([])

            let store = TestStore(initialState: ChatWalletAddress.State()) {
                ChatWalletAddress()
            } withDependencies: {
                $0.mainQueue = DispatchQueue.test.eraseToAnyScheduler()
                $0.pasteboard.setString = { value in copied.withValue { $0.append(value.data) } }
            }
            store.exhaustivity = .off

            await store.send(.copyAddressTapped(""))

            #expect(copied.value.isEmpty)
            #expect(store.state.copiedAddress == nil)
        }
    }
}
