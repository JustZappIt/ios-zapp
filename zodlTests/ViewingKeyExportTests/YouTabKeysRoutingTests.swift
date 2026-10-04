//
//  YouTabKeysRoutingTests.swift
//  zodlTests
//
//  Root routing for the You tab's Hardware wallet and Export viewing key rows, and the P2P key
//  screen pushed over Profile & identity. `Root.State.path` holds ONE destination, so each screen
//  has to name where back goes. Pure state moves through `coordinatorReduce()`, as in
//  `ChatProfileRoutingTests`.
//

import ComposableArchitecture
import Foundation
import Testing
@testable @preconcurrency import ZcashLightClientKit
@testable import zodl_internal

/// Serialized: `Root.State.initial` touches process-global `@Shared(.inMemory(...))` keys.
@Suite(.serialized) struct YouTabKeysRoutingTests {
    private func route(from path: Root.State.Path?, _ action: Root.Action, state initial: Root.State? = nil) -> Root.State {
        var state = initial ?? Root.State.initial
        state.path = path
        _ = Root().coordinatorReduce()._reduce(into: &state, action: action)

        return state
    }

    private static func walletAccount(idByte: UInt8, keystone: Bool) -> WalletAccount {
        WalletAccount(
            Account(
                id: AccountUUID(id: [UInt8](repeating: idByte, count: 16)),
                name: keystone ? "Keystone" : "Zapp",
                keySource: keystone ? String(localizable: .accountsKeystone).lowercased() : nil,
                seedFingerprint: nil,
                hdAccountIndex: Zip32AccountIndex(0),
                ufvk: nil,
                uivk: nil
            )
        )
    }

    // MARK: - Hardware wallet

    @Test func theHardwareWalletRowOpensTheWalletsSheetOverTheTabs() {
        withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let state = route(from: nil, .zappTabs(.hardwareWalletTapped))

            #expect(state.homeState.accountSwitchRequest)
            #expect(state.path == nil)
        }
    }

    /// The sheet sends Home's own actions, so Root's existing switch applies: the selection moves
    /// to the tapped account, which is what every account-scoped Zapp surface (Pay balance and
    /// activity, P2P gating) reads.
    @Test func pickingAnAccountInTheSheetSwitchesTheSelection() {
        withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let zapp = Self.walletAccount(idByte: 10, keystone: false)
            let keystone = Self.walletAccount(idByte: 11, keystone: true)
            var initial = Root.State.initial
            initial.$selectedWalletAccount.withLock { $0 = zapp }
            initial.homeState.transactionListState.isInvalidated = false

            let state = route(from: nil, .home(.walletAccountTapped(keystone)), state: initial)

            #expect(state.selectedWalletAccount == keystone)
            #expect(state.homeState.isKeystoneAccountActive)
            #expect(state.homeState.transactionListState.isInvalidated)
        }
    }

    @MainActor @Test func pickingAnAccountClosesTheSheet() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = Home.State.initial
            state.accountSwitchRequest = true
            let store = TestStore(initialState: state) {
                Home()
            }
            store.exhaustivity = .off

            await store.send(.walletAccountTapped(Self.walletAccount(idByte: 12, keystone: true)))

            #expect(store.state.accountSwitchRequest == false)
        }
    }

    @Test func connectHardwareWalletOpensTheKeystoneFlow() {
        withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let state = route(from: nil, .home(.addKeystoneHWWalletTapped))

            #expect(state.path == .addKeystoneHWWalletCoordFlow)
        }
    }

    /// Android's promo link carries Zapp's discount code, which the promo copy names.
    @Test func theKeystonePromoCarriesZappsCode() {
        withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            #expect(Home.State.initial.inAppBrowserURLKeystone.hasSuffix("discount=Zapp"))
        }
    }

    // MARK: - Viewing key

    @Test func theViewingKeyRowPushesTheExportScreen() {
        withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let state = route(from: nil, .zappTabs(.viewingKeyExportTapped))

            #expect(state.path == .viewingKeyExport)
        }
    }

    @Test func viewingKeyBackReturnsToTheTabs() {
        withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            #expect(route(from: .viewingKeyExport, .viewingKeyExport(.backTapped)).path == nil)
        }
    }

    // MARK: - P2P key

    @Test func theP2pKeyRowPushesTheKeyScreen() {
        withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            #expect(route(from: .chatProfile, .chatProfile(.p2pKeyScreenTapped)).path == .chatP2pKey)
        }
    }

    @Test func p2pKeyBackReturnsToTheProfileNotTheTabs() {
        withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            #expect(route(from: .chatP2pKey, .chatP2pKey(.backTapped)).path == .chatProfile)
        }
    }

    /// Neither screen broadcasts, so an automatic server switch may run under them.
    @Test func neitherKeyScreenIsASensitiveFlow() {
        withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = Root.State.initial
            state.path = .viewingKeyExport
            #expect(!state.isSensitiveFlowActive)

            state.path = .chatP2pKey
            #expect(!state.isSensitiveFlowActive)
        }
    }
}
