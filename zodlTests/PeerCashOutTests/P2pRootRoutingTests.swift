// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Testing
@testable @preconcurrency import ZcashLightClientKit
@testable import zodl_internal

/// Serialized because `Root.State.initial` resolves process-global `@Shared` keys.
@Suite(.serialized)
struct P2pRootRoutingTests {
    @Test func activityOpenedFromOfframpReturnsToTheSameOfframp() {
        withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = Root.State.initial
            state.path = .offramp
            state.offrampState.page = .topUp

            reduce(&state, .offramp(.delegate(.openActivity)))
            #expect(state.path == .p2pActivity)
            #expect(state.p2pActivityOrigin == .offramp)

            reduce(&state, .p2pActivity(.delegate(.close)))
            #expect(state.path == .offramp)
            #expect(state.offrampState.page == .topUp)
        }
    }

    @Test func activityAttemptStartsFromCleanStateAndBackReturnsToActivity() {
        withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = Root.State.initial
            state.path = .p2pActivity
            state.peerCashOutState.order = PeerOrderDetail.State(depositID: "stale-order")

            reduce(
                &state,
                .p2pActivity(.delegate(.openPeerAttempt(
                    attemptID: "attempt-1",
                    destinationCode: "monzo"
                )))
            )

            #expect(state.path == .peerCashOut)
            #expect(state.peerCashOutOrigin == .activity)
            #expect(state.peerCashOutState.form.destinationCode == "monzo")
            #expect(state.peerCashOutState.progress?.attemptID == "attempt-1")
            #expect(state.peerCashOutState.order == nil)

            reduce(&state, .peerCashOut(.progress(.delegate(.close))))
            #expect(state.path == .p2pActivity)
        }
    }

    @Test func directActivityOrderBackReturnsToActivityInsteadOfTheCashOutForm() {
        withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = Root.State.initial
            state.path = .p2pActivity

            reduce(
                &state,
                .p2pActivity(.delegate(.openPeerOrder(
                    depositID: "escrow-1",
                    destinationCode: "revolut"
                )))
            )
            #expect(state.peerCashOutState.progress == nil)
            #expect(state.peerCashOutState.order?.depositID == "escrow-1")

            reduce(&state, .peerCashOut(.order(.delegate(.close))))
            #expect(state.path == .p2pActivity)
        }
    }

    @Test func activityRecoveryOfframpReturnsToActivity() {
        withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = Root.State.initial
            state.path = .p2pActivity

            reduce(&state, .p2pActivity(.delegate(.recoverScanAndPayOrder(orderID: "42"))))
            #expect(state.path == .offramp)
            #expect(state.offrampOrigin == .activity)

            reduce(&state, .offramp(.delegate(.close)))
            #expect(state.path == .p2pActivity)
        }
    }

    @Test func activityRecoveryDoesNotReplaceItsOriginatingOfframpState() {
        withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = Root.State.initial
            state.path = .offramp
            state.offrampState.page = .topUp
            state.offrampState.selectedCurrencyCode = "INR"

            reduce(&state, .offramp(.delegate(.openActivity)))
            reduce(&state, .p2pActivity(.delegate(.recoverScanAndPayOrder(orderID: "42"))))
            reduce(&state, .offramp(.delegate(.close)))
            #expect(state.path == .p2pActivity)

            reduce(&state, .p2pActivity(.delegate(.close)))
            #expect(state.path == .offramp)
            #expect(state.offrampState.page == .topUp)
            #expect(state.offrampState.selectedCurrencyCode == "INR")
        }
    }

    @Test func nestedPeerTopUpActivityEntryRestoresTheOriginalCashOutForm() {
        withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = Root.State.initial
            state.path = .peerCashOut
            state.peerCashOutState = PeerCashOut.State(destinationCode: "revolut")
            state.peerCashOutState.form.handleInput = "original-payee"

            reduce(&state, .peerCashOut(.delegate(.topUp)))
            reduce(&state, .offramp(.delegate(.openActivity)))
            reduce(
                &state,
                .p2pActivity(.delegate(.openPeerOrder(
                    depositID: "escrow-from-activity",
                    destinationCode: "monzo"
                )))
            )
            reduce(&state, .peerCashOut(.order(.delegate(.close))))
            reduce(&state, .p2pActivity(.delegate(.close)))
            reduce(&state, .offramp(.delegate(.close)))

            #expect(state.path == .peerCashOut)
            #expect(state.peerCashOutState.form.destinationCode == "revolut")
            #expect(state.peerCashOutState.form.handleInput == "original-payee")
            #expect(state.peerCashOutState.order == nil)
        }
    }

    @MainActor
    @Test func removedSavedPeerDestinationFallsBackToScanAndPay() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = Root.State.initial
            state.$selectedWalletAccount.withLock { $0 = softwareWallet() }
            let supported = PeerDestination(
                code: "revolut",
                currencies: [],
                defaultCurrencyCodes: [],
                validatesHandleLive: true,
                offersCurrencyChoice: false
            )
            let store = TestStore(initialState: state) {
                Root().coordinatorReduce()
            } withDependencies: {
                $0.peerCashOut.isConfigured = { true }
                $0.peerCashOut.capabilities = {
                    PeerCapabilities(
                        isAvailable: true,
                        destinations: [supported],
                        recommendedMinimum: .zero,
                        attemptIDByteCount: 16
                    )
                }
                $0.userStoredPreferences.p2pRail = { .peerCashOut(destinationCode: "removed-destination") }
            }

            await store.send(.home(.payWithNearTapped))
            // Asserted explicitly rather than through a state-diff closure: `Root.State` is not
            // Equatable, so TestStore cannot detect the change and reports the closure as a no-op.
            await store.receive(\.openScanAndPay)

            #expect(store.state.path == .offramp)
            #expect(store.state.offrampOrigin == .pay)
        }
    }

    /// The capability read throws for an outage as well as for an absent rail. Reading the first as
    /// the second would silently open the other product, which is not a way to report a network
    /// error — the rail the user chose opens and reports its own.
    @MainActor
    @Test func anUnreadableCapabilityKeepsTheChosenRailInsteadOfSwitchingProducts() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = Root.State.initial
            state.$selectedWalletAccount.withLock { $0 = softwareWallet() }
            let store = TestStore(initialState: state) {
                Root().coordinatorReduce()
            } withDependencies: {
                $0.peerCashOut.isConfigured = { true }
                $0.peerCashOut.capabilities = { throw PeerCashOutClientError.unavailable }
                $0.userStoredPreferences.p2pRail = { .peerCashOut(destinationCode: "revolut") }
            }

            await store.send(.home(.payWithNearTapped))
            await store.receive(\.openPeerCashOut)

            #expect(store.state.path == .peerCashOut)
            #expect(store.state.peerCashOutState.form.destinationCode == "revolut")
        }
    }

    /// A hardware wallet cannot derive the Base account the rails sign from, and the answer is on
    /// the device: no client is built and no read can fail on the way to it.
    @MainActor
    @Test func aWalletWithoutTheRailsGoesStraightToScanAndPay() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = Root.State.initial
            state.$selectedWalletAccount.withLock { $0 = softwareWallet() }
            let store = TestStore(initialState: state) {
                Root().coordinatorReduce()
            } withDependencies: {
                $0.peerCashOut.isConfigured = { false }
                $0.peerCashOut.capabilities = { Issue.record("capabilities must not be read"); return .unavailable }
                $0.userStoredPreferences.p2pRail = { .peerCashOut(destinationCode: "revolut") }
            }

            await store.send(.home(.payWithNearTapped))
            await store.receive(\.openScanAndPay)

            #expect(store.state.path == .offramp)
        }
    }

    private func reduce(_ state: inout Root.State, _ action: Root.Action) {
        _ = Root().coordinatorReduce()._reduce(into: &state, action: action)
    }

    private func softwareWallet() -> WalletAccount {
        WalletAccount(
            Account(
                id: AccountUUID(id: [UInt8](repeating: 7, count: 16)),
                name: "Zapp",
                keySource: nil,
                seedFingerprint: [1],
                hdAccountIndex: Zip32AccountIndex(0),
                ufvk: nil,
                uivk: nil
            )
        )
    }
}
