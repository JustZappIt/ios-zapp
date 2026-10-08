//
//  WalletFundingTests.swift
//  zodlTests
//
//  The empty-wallet gate (Android's `ObserveFundingUseCase`, PR #86): which wallets are called
//  empty, and the five money screens that show "Add ZEC" in place of their form.
//

import ComposableArchitecture
import Foundation
import Testing
@testable @preconcurrency import ZcashLightClientKit
@testable import zodl_internal

// MARK: - The rule

struct WalletFundingRuleTests {
    @Test func aSyncedWalletHoldingNothingIsEmpty() {
        #expect(WalletFunding.next(previous: .unknown, total: .zero, isUpToDate: true, isRestoring: false) == .empty)
    }

    @Test func anyBalanceIsFundedWhateverTheSyncState() {
        #expect(WalletFunding.next(previous: .empty, total: Zatoshi(1), isUpToDate: false, isRestoring: true) == .funded)
    }

    @Test func anUnsyncedWalletIsNotCalledEmpty() {
        #expect(WalletFunding.next(previous: .unknown, total: .zero, isUpToDate: false, isRestoring: false) == .unknown)
    }

    @Test func aRestoringWalletIsNotCalledEmptyEvenWhenUpToDate() {
        #expect(WalletFunding.next(previous: .unknown, total: .zero, isUpToDate: true, isRestoring: true) == .unknown)
    }

    @Test func noBalanceReadYetIsUnknown() {
        #expect(WalletFunding.next(previous: .empty, total: nil, isUpToDate: true, isRestoring: false) == .unknown)
    }

    @Test func emptyHoldsThroughTheCatchUpSyncEachNewBlockStarts() {
        #expect(WalletFunding.next(previous: .empty, total: .zero, isUpToDate: false, isRestoring: false) == .empty)
    }

    @Test func emptyGivesWayAsSoonAsFundsArrive() {
        #expect(WalletFunding.next(previous: .empty, total: Zatoshi(10), isUpToDate: false, isRestoring: false) == .funded)
    }

    @Test func usdcOnBaseFundsAFlowThatCanPayFromIt() {
        #expect(WalletFunding.empty.withBaseUsdc(Decimal(string: "0.5")) == .funded)
    }

    @Test func emptyZecAndZeroUsdcIsEmpty() {
        #expect(WalletFunding.empty.withBaseUsdc(0) == .empty)
    }

    @Test func anUnreadBaseBalanceIsNeverCalledEmpty() {
        #expect(WalletFunding.empty.withBaseUsdc(nil) == .unknown)
    }

    @Test func zecAloneFundsTheFlowWhateverBaseSays() {
        #expect(WalletFunding.funded.withBaseUsdc(nil) == .funded)
    }
}

// MARK: - The screens

// Serialized: every case writes the process-global `walletFunding` shared store.
@Suite(.serialized) @MainActor struct WalletFundingScreenTests {
    private func setFunding(_ funding: WalletFunding) {
        @Shared(.inMemory(.walletFunding)) var walletFunding: WalletFunding = .unknown
        $walletFunding.withLock { $0 = funding }
    }

    @Test func sendAndSwapOfferAddZecInPlaceOfTheForm() {
        setFunding(.empty)
        defer { setFunding(.unknown) }

        var state = SendCoordFlow.State()
        #expect(state.showsAddFundsPanel)
        #expect(state.primaryButton == .addZec)

        state.mode = .swap
        #expect(state.primaryButton == .addZec)
    }

    @Test func anUnknownWalletKeepsTheSendForm() {
        setFunding(.unknown)

        let state = SendCoordFlow.State()
        #expect(!state.showsAddFundsPanel)
        #expect(state.primaryButton != .addZec)
    }

    @Test func giftShowsThePanelOnlyOnItsDetailsStep() {
        setFunding(.empty)
        defer { setFunding(.unknown) }

        let state = GiftCard.State()
        #expect(state.visibleStage == .details)
        #expect(state.showsAddFundsPanel)
    }

    @Test func giftAddZecOpensTheTopUpPickerAndHandsThePickToRoot() async {
        setFunding(.empty)
        defer { setFunding(.unknown) }

        let store = TestStore(initialState: GiftCard.State()) { GiftCard() }
        store.exhaustivity = .off

        await store.send(.addZecTapped) { $0.isTopUpPresented = true }
        // The delegate it sends is routed by Root: see the Receive test below.
        await store.send(.topUpSourcePicked(.exchange)) { $0.isTopUpPresented = false }
    }

    @Test func payAMerchantWaitsForTheBaseBalanceBeforeCallingItEmpty() {
        setFunding(.empty)
        defer { setFunding(.unknown) }

        var state = Offramp.State(page: .amount, corridorContext: .payment)
        #expect(!state.showsPayAddFundsPanel)

        state.account = account(balanceMicros: "0")
        #expect(state.showsPayAddFundsPanel)

        state.account = account(balanceMicros: "5000000")
        #expect(!state.showsPayAddFundsPanel)
    }

    @Test func anOrderInFlightKeepsThePayForm() {
        setFunding(.empty)
        defer { setFunding(.unknown) }

        var state = Offramp.State(page: .amount, corridorContext: .payment)
        state.account = account(balanceMicros: "0")
        state.hasCheckpoint = true
        #expect(!state.showsPayAddFundsPanel)
    }

    @Test func addFundsToBaseGatesItsAmountStepUnlessATopUpIsSaved() {
        setFunding(.empty)
        defer { setFunding(.unknown) }

        var state = Offramp.State(page: .topUp, corridorContext: .settings)
        #expect(state.showsTopUpAddFundsPanel)

        state.hasTopUpCheckpoint = true
        #expect(!state.showsTopUpAddFundsPanel)
    }

    @Test func aTopUpPickedFromGiftOpensReceiveOnTheTransparentAddress() async {
        var state = Root.State.initial
        state.path = .giftCard
        state.$selectedWalletAccount.withLock { $0 = nil }

        let store = TestStore(initialState: state) { Root() } withDependencies: {
            $0.sdkSynchronizer = .noOp
        }
        store.exhaustivity = .off

        await store.send(.giftCard(.delegate(.topUpSourcePicked(.exchange)))) {
            $0.receiveFocusOnOpen = .tAddress
        }
        await store.receive(\.home.receiveScreenRequested)
        await store.receive(\.home.receiveTapped) {
            $0.receiveFocusOnOpen = nil
            $0.path = .receive
        }
        #expect(store.state.receiveState.currentFocus == .tAddress)
        // Receive re-applies this on appear, so the view can't snap back to shielded.
        #expect(store.state.receiveState.focusOnAppear == .tAddress)
    }

    private func account(balanceMicros: String) -> OfframpAccountModel {
        OfframpAccountModel(
            address: "0xabc",
            balanceMicros: balanceMicros,
            balanceDisplay: nil,
            explorerURL: nil,
            canBridgeToBase: true,
            canRefundToZec: false
        )
    }
}
