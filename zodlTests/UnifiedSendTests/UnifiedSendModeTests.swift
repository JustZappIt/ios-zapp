//
//  UnifiedSendModeTests.swift
//  zodlTests
//
//  Phase 12 — the unified send form. One screen switches between a direct ZEC send and a swap from
//  its inline asset selector (Android's `UnifiedSendVM`: `isSwap = selectedAsset !is ZecSwapAsset`).
//  These tests pin the mode machine, the primary-button states including Top Up, the ZIP-321 scan
//  gate, and — most importantly — that neither mode broadcasts from the coordinator: both submit
//  through a `SendConfirmation` path element, which owns the only transaction-guarded calls.
//
//  `SendCoordFlow.State` is not Equatable, so these drive a plain `Store` (the approach the Swap /
//  Scan CoordFlow suites already use). NOTE: `SendForm.State.amount` and `SwapAndPay.State.amount`
//  are `_XCTIsTesting`-poisoned to 0, so any assertion that needs a non-zero amount is called out
//  rather than faked.
//

import ComposableArchitecture
import Foundation
import Testing
@testable @preconcurrency import ZcashLightClientKit
@testable import zodl_internal

// Serialized: drives TCA stores that touch process-global `@Shared` state.
@Suite(.serialized) @MainActor struct UnifiedSendModeTests {
    private static let zcashAddress = "tmP3uLtGx5GPddkq8a6ddmXhqJJ3vy6tpTE"

    private static func quote(depositAddress: String, amountIn: Decimal) -> SwapQuote {
        SwapQuote(
            depositAddress: depositAddress,
            destinationAddress: "bc1qexampleaddress",
            refundAddress: "utest1refund",
            originAssetId: "zec",
            destinationAssetId: "btc-BTC",
            amountIn: amountIn,
            amountInUsd: "1.00",
            minAmountIn: 0,
            amountOut: 1,
            amountOutUsd: "1.00",
            timeEstimate: 60
        )
    }

    private func swapAsset(chain: String = "btc", token: String = "BTC") -> SwapAsset {
        SwapAsset(provider: "near", chain: chain, token: token, assetId: "\(chain)-\(token)", usdPrice: 100, decimals: 8)
    }

    private func store(
        shieldedBalance: Zatoshi = Zatoshi(100_000_000),
        mode: SendCoordFlow.Mode = .zec
    ) -> StoreOf<SendCoordFlow> {
        var state = SendCoordFlow.State()
        state.mode = mode
        state.sendFormState.walletBalancesState.shieldedBalance = shieldedBalance
        state.sendFormState.shieldedBalance = shieldedBalance
        state.swapState.walletBalancesState.shieldedBalance = shieldedBalance

        return Store(initialState: state) {
            SendCoordFlow()
        } withDependencies: {
            $0.audioServices = AudioServicesClient(systemSoundVibrate: { })
            $0.derivationTool = .liveValue
            $0.exchangeRate = .noOp
            $0.mainQueue = .immediate
            $0.numberFormatter = .liveValue
            $0.sdkSynchronizer = .noOp
            $0.userMetadataProvider.markTransactionAsSwapFor = { _, _, _, _, _, _, _, _, _ in }
            $0.userMetadataProvider.store = { _ in }
            $0.zcashSDKEnvironment = .testnet
        }
    }

    // MARK: - Mode switching

    /// The flow opens as a ZEC send: no swap asset is shown even though `SwapAndPay` pre-selects one
    /// of its own accord for the picker's benefit.
    @Test func startsInZecMode() {
        let store = store()

        #expect(store.mode == .zec)
        #expect(!store.isSwap)
        #expect(store.selectedSwapAsset == nil)
    }

    /// Picking a non-ZEC asset turns the same screen into a swap, and forces Android's EXACT_INPUT
    /// direction (spend ZEC, receive the asset). Swap-to-ZEC is never entered from here.
    @Test func pickingANonZecAssetSwitchesToSwapMode() async {
        let store = store()

        store.send(.swapAssetSelected(swapAsset()))
        await Task.yield()

        #expect(store.mode == .swap)
        #expect(store.isSwap)
        #expect(store.selectedSwapAsset?.token == "BTC")
        #expect(store.swapState.isSwapExperienceEnabled)
        #expect(!store.swapState.isSwapToZecExperienceEnabled)
        #expect(!store.isAssetPickerPresented)
    }

    /// Android clears the recipient whenever the asset id changes — an address for one chain is
    /// meaningless on another.
    @Test func switchingToSwapClearsTheZecRecipient() async {
        let store = store()

        store.send(.sendForm(.addressUpdated(Self.zcashAddress.redacted)))
        await waitFor { store.sendFormState.isValidAddress }

        store.send(.swapAssetSelected(swapAsset()))
        await waitFor { store.sendFormState.address.data.isEmpty }

        #expect(store.sendFormState.address.data.isEmpty)
        #expect(!store.sendFormState.isValidAddress)
        #expect(store.swapState.address.isEmpty)
    }

    /// ...and switching back to ZEC clears the swap recipient and the contact chip with it.
    @Test func switchingBackToZecClearsTheSwapRecipient() async {
        let store = store(mode: .swap)

        store.send(.swapAssetSelected(swapAsset()))
        await Task.yield()
        store.send(.swap(.binding(.set(\.address, "bc1qexampleaddress"))))
        await Task.yield()

        #expect(!store.swapState.address.isEmpty)

        store.send(.zecAssetSelected)
        await waitFor { store.mode == .zec }

        #expect(store.mode == .zec)
        #expect(store.swapState.address.isEmpty)
        #expect(store.swapState.selectedContact == nil)
    }

    /// The ZEC-denominated amount survives a mode switch (Android keeps its amount fields across
    /// the asset change; only the recipient is cleared).
    @Test func theZecAmountIsCarriedAcrossAModeSwitch() async {
        let store = store()

        store.send(.sendForm(.zecAmountUpdated("1.25".redacted)))
        await waitFor { store.sendFormState.zecAmountText.data == "1.25" }

        store.send(.swapAssetSelected(swapAsset()))
        await waitFor { store.swapState.amountText == "1.25" }

        #expect(store.swapState.amountText == "1.25")
        #expect(!store.swapState.isInputInUsd)
    }

    @Test func theSwapAmountIsCarriedBackToZec() async {
        let store = store(mode: .swap)

        store.send(.swapAssetSelected(swapAsset()))
        await Task.yield()
        store.send(.swap(.binding(.set(\.amountText, "0.5"))))
        await Task.yield()

        store.send(.zecAssetSelected)
        await waitFor { store.sendFormState.zecAmountText.data == "0.5" }

        #expect(store.sendFormState.zecAmountText.data == "0.5")
    }

    /// The amount swap affordance is ZEC-mode only — swap mode has `SwapAndPay`'s own USD toggle.
    @Test func amountInputSwapIsIgnoredInSwapMode() async {
        let store = store(mode: .swap)

        store.send(.amountInputSwapped)
        await Task.yield()

        #expect(!store.isFiatPrimary)
    }

    @Test func amountInputSwapFlipsTheLeadingFieldInZecMode() async {
        let store = store()

        store.send(.amountInputSwapped)
        await Task.yield()

        #expect(store.isFiatPrimary)
    }

    // MARK: - Primary button (Android's `buildPrimaryButton`)

    /// Android shows Top Up before any amount is entered when the spendable balance is zero — but
    /// only in ZEC-direct mode.
    @Test func zeroBalanceInZecModeOffersTopUp() {
        let store = store(shieldedBalance: .zero)

        #expect(store.hasZeroBalance)
        #expect(store.primaryButton == .topUp)
        #expect(store.isTopUpFooterVisible)
    }

    @Test func zeroBalanceInSwapModeDoesNotOfferTopUp() async {
        let store = store(shieldedBalance: .zero, mode: .swap)

        store.send(.swapAssetSelected(swapAsset()))
        await Task.yield()

        #expect(store.hasZeroBalance)
        #expect(store.primaryButton != .topUp)
        #expect(!store.isTopUpFooterVisible)
    }

    /// A funded wallet with an empty form has nothing to review yet.
    @Test func anEmptyFundedFormDisablesTheCta() {
        let store = store()

        #expect(store.primaryButton == .disabled)
        #expect(!store.isTopUpFooterVisible)
    }

    /// A valid recipient on a funded wallet is reviewable. (The amount is `_XCTIsTesting`-poisoned
    /// to zero, which `SendForm.isValidForm` treats as a valid amount — the same assumption the
    /// pre-existing SendForm suite works under.)
    @Test func aValidZecRecipientEnablesReview() async {
        let store = store()

        store.send(.sendForm(.addressUpdated(Self.zcashAddress.redacted)))
        await waitFor { store.primaryButton == .review }

        #expect(store.primaryButton == .review)
    }

    // MARK: - ZIP-321 scan gate (Android's `UnifiedSendArgs.isScanZip321Enabled`)

    @Test func theInFormScannerAcceptsZip321ByDefault() async {
        let store = store()

        store.send(.sendForm(.scanTapped))
        await waitFor { store.path.count == 1 }

        guard case .scan(let scanState) = store.path.last else {
            Issue.record("expected the scanner to be pushed")
            return
        }
        #expect(scanState.checkers.count == 2)
    }

    /// "Send again" opens the form with ZIP-321 scanning off, so the scanner can only yield a plain
    /// address — no payment request can be picked up and auto-proposed.
    @Test func sendAgainDisablesZip321Scanning() async {
        var state = SendCoordFlow.State()
        state.isScanZip321Enabled = false
        state.sendFormState.walletBalancesState.shieldedBalance = Zatoshi(100_000_000)
        let store = Store(initialState: state) {
            SendCoordFlow()
        } withDependencies: {
            $0.audioServices = AudioServicesClient(systemSoundVibrate: { })
            $0.derivationTool = .liveValue
            $0.exchangeRate = .noOp
            $0.mainQueue = .immediate
            $0.numberFormatter = .liveValue
            $0.sdkSynchronizer = .noOp
            $0.userMetadataProvider.markTransactionAsSwapFor = { _, _, _, _, _, _, _, _, _ in }
            $0.userMetadataProvider.store = { _ in }
            $0.zcashSDKEnvironment = .testnet
        }

        store.send(.sendForm(.scanTapped))
        await waitFor { store.path.count == 1 }

        guard case .scan(let scanState) = store.path.last else {
            Issue.record("expected the scanner to be pushed")
            return
        }
        #expect(scanState.checkers.count == 1)
    }

    /// Swap mode scans a raw destination on the picked chain, not a Zcash address.
    @Test func swapModeScannerUsesTheSwapChecker() async {
        let store = store(mode: .swap)

        store.send(.swap(.scanTapped))
        await waitFor { store.path.count == 1 }

        guard case .scan(let scanState) = store.path.last else {
            Issue.record("expected the scanner to be pushed")
            return
        }
        #expect(scanState.checkers.count == 1)

        // The coordinator pops the scanner in the same reduction that consumes its result, so TCA's
        // `forEach` then sees an action for an element that is already gone and reports it. That is
        // the established pattern in this flow (the ZEC `scan(.foundAddress)` case does exactly the
        // same, as do the sibling Scan/SwapAndPay coordinators), so it is expected here rather than
        // restructured inside a money path.
        await withKnownIssue {
            store.send(.path(.element(id: store.path.ids[0], action: .scan(.foundString("bc1qscanned")))))
            await waitFor { store.swapState.address == "bc1qscanned" }
        }

        #expect(store.swapState.address == "bc1qscanned")
        #expect(store.path.isEmpty)
    }

    // MARK: - Submission routes through SendConfirmation (transaction-guard discipline)

    /// ZEC-direct review pushes `sendConfirmation`; that element — not this coordinator — is what
    /// eventually calls the guarded `createAndSubmitProposedTransactions`.
    @Test func zecReviewPushesSendConfirmation() async {
        let store = store()

        store.send(.sendForm(.confirmationRequired(.send)))
        await waitFor { store.path.count == 1 }

        guard case .sendConfirmation(let confirmation) = store.path.last else {
            Issue.record("expected sendConfirmation to be pushed")
            return
        }
        #expect(confirmation.type == .regular)
    }

    /// Cancelling the app-lock prompt must leave the user on the form, not on a sending screen that
    /// will never finish.
    @Test func aRefusedAppLockNeverPushesTheSendingScreen() async {
        let store = swapReadyStore(authenticates: false)

        store.send(.swap(.confirmButtonTapped))
        await Task.yield()
        try? await Task.sleep(nanoseconds: 200_000_000)

        #expect(store.path.isEmpty)
    }

    /// Confirming a swap quote pushes `sending` with a swap-typed `SendConfirmation` and hands the
    /// broadcast to it. No `sdkSynchronizer` submit closure is called from the coordinator: the
    /// no-op synchronizer here would trap if it were.
    @Test func swapConfirmPushesSwapTypedSendingRatherThanBroadcastingItself() async {
        let store = swapReadyStore(authenticates: true)

        store.send(.swap(.confirmButtonTapped))
        await waitFor { store.path.count == 1 }

        guard case .sending(let confirmation) = store.path.last else {
            Issue.record("expected sending to be pushed")
            return
        }
        #expect(confirmation.type == .swap)
        #expect(confirmation.address == Self.zcashAddress)
        #expect(confirmation.proposal != nil)
    }

    /// In swap mode the CTA tap is itself what pushes the broadcasting element, so a second tap
    /// delivered while the quote sheet animates away must not push a second one: the transaction
    /// guard is a FIFO mutex and would happily run the same proposal twice in a row.
    @Test func aDoubleTappedSwapConfirmSubmitsOnlyOnce() async {
        let store = swapReadyStore(authenticates: true)

        store.send(.swap(.confirmButtonTapped))
        store.send(.swap(.confirmButtonTapped))
        await waitFor { store.path.count >= 1 }
        try? await Task.sleep(nanoseconds: 200_000_000)

        #expect(store.path.filter { $0.is(\.sending) }.count == 1)
    }

    /// Same guard on the authorised push itself: two app-lock prompts can both succeed.
    @Test func aSecondAuthorisedSwapSendIsIgnored() async {
        let store = swapReadyStore(authenticates: true)

        store.send(.swapSendAuthorized)
        await waitFor { store.path.contains { $0.is(\.sending) } }

        store.send(.swapSendAuthorized)
        try? await Task.sleep(nanoseconds: 200_000_000)

        #expect(store.path.filter { $0.is(\.sending) }.count == 1)
    }

    /// And on the Keystone branch, whose push starts the PCZT chain that ends in the guarded
    /// `createAndSubmitTransactionFromPCZT`.
    @Test func aDoubleTappedKeystoneSwapConfirmPushesOnce() async {
        let store = swapReadyStore(authenticates: true)

        store.send(.swap(.confirmWithKeystoneTapped))
        await waitFor { store.path.contains { $0.is(\.confirmWithKeystone) } }

        store.send(.swap(.confirmWithKeystoneTapped))
        try? await Task.sleep(nanoseconds: 200_000_000)

        #expect(store.path.filter { $0.is(\.confirmWithKeystone) }.count == 1)
    }

    /// Shared fixture: a swap form holding a quote and a proposal, ready to confirm.
    private func swapReadyStore(authenticates: Bool) -> StoreOf<SendCoordFlow> {
        var state = SendCoordFlow.State()
        state.mode = .swap
        state.sendFormState.walletBalancesState.shieldedBalance = Zatoshi(100_000_000)
        state.swapState.selectedAsset = swapAsset()
        state.swapState.zecAsset = SwapAsset(
            provider: "near", chain: "zec", token: "ZEC", assetId: "zec", usdPrice: 50, decimals: 8
        )
        state.swapState.address = "bc1qexampleaddress"
        state.swapState.proposal = .testOnlyFakeProposal(totalFee: 10_000)
        state.swapState.quote = Self.quote(depositAddress: Self.zcashAddress, amountIn: 100_000)

        return Store(initialState: state) {
            SendCoordFlow()
        } withDependencies: {
            $0.audioServices = AudioServicesClient(systemSoundVibrate: { })
            $0.derivationTool = .liveValue
            $0.exchangeRate = .noOp
            $0.localAuthentication.authenticate = { authenticates }
            $0.mainQueue = .immediate
            $0.numberFormatter = .liveValue
            $0.sdkSynchronizer = .noOp
            $0.userMetadataProvider.markTransactionAsSwapFor = { _, _, _, _, _, _, _, _, _ in }
            $0.userMetadataProvider.store = { _ in }
            $0.zcashSDKEnvironment = .testnet
        }
    }

    /// Keystone swaps take the PCZT chain, which submits through
    /// `createAndSubmitTransactionFromPCZT` — again inside `SendConfirmation`.
    @Test func swapKeystoneConfirmPushesSwapTypedPcztConfirmation() async {
        var state = SendCoordFlow.State()
        state.mode = .swap
        state.swapState.selectedAsset = swapAsset()
        state.swapState.proposal = .testOnlyFakeProposal(totalFee: 10_000)
        state.swapState.quote = Self.quote(depositAddress: Self.zcashAddress, amountIn: 100_000)

        let store = Store(initialState: state) {
            SendCoordFlow()
        } withDependencies: {
            $0.audioServices = AudioServicesClient(systemSoundVibrate: { })
            $0.derivationTool = .liveValue
            $0.exchangeRate = .noOp
            $0.mainQueue = .immediate
            $0.numberFormatter = .liveValue
            $0.sdkSynchronizer = .noOp
            $0.userMetadataProvider.markTransactionAsSwapFor = { _, _, _, _, _, _, _, _, _ in }
            $0.userMetadataProvider.store = { _ in }
            $0.zcashSDKEnvironment = .testnet
        }

        store.send(.swap(.confirmWithKeystoneTapped))
        await waitFor { store.path.count >= 1 }

        guard case .confirmWithKeystone(let confirmation) = store.path.first else {
            Issue.record("expected confirmWithKeystone to be pushed")
            return
        }
        #expect(confirmation.type == .swap)
    }

    /// Back with a quote request in flight asks before throwing it away (Android's `onBack`).
    @Test func backDuringAQuoteRequestOpensTheCancelSheet() async {
        var state = SendCoordFlow.State()
        state.mode = .swap
        state.swapState.isQuoteRequestInFlight = true

        let store = Store(initialState: state) {
            SendCoordFlow()
        } withDependencies: {
            $0.audioServices = AudioServicesClient(systemSoundVibrate: { })
            $0.derivationTool = .liveValue
            $0.mainQueue = .immediate
            $0.numberFormatter = .liveValue
            $0.sdkSynchronizer = .noOp
            $0.zcashSDKEnvironment = .testnet
        }

        store.send(.backButtonTapped)
        await waitFor { store.swapState.isCancelSheetVisible }

        #expect(store.swapState.isCancelSheetVisible)
    }
}

@MainActor
private func waitFor(
    timeoutNanoseconds: UInt64 = 10_000_000_000,
    sourceLocation: SourceLocation = #_sourceLocation,
    condition: @escaping @MainActor () -> Bool
) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while !condition(), DispatchTime.now().uptimeNanoseconds < deadline {
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    #expect(condition(), "Timed out waiting for the unified send store", sourceLocation: sourceLocation)
}
