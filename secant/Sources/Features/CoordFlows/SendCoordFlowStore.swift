//
//  SendCoordFlowStore.swift
//  Zashi
//
//  Created by Lukáš Korba on 2025-03-18.
//

import SwiftUI
import ComposableArchitecture
@preconcurrency import ZcashLightClientKit

/// The **unified send flow** — iOS's counterpart to Android's `UnifiedSendScreen`
/// (`A:screen/unifiedsend/`). Every send entry point on the Pay tab, in a chat room and in
/// transaction detail ("send again") lands on this flow's root screen, `ZappUnifiedSendView`, whose
/// inline asset selector switches the *same* screen between a direct ZEC send and a swap —
/// Android's `UnifiedSendVM.kt:390` (`isSwap = selectedAsset !is ZecSwapAsset`).
///
/// The flow composes the two existing form reducers rather than merging them:
/// `SendForm` drives ZEC-direct mode (address validation, TEX gating, ZIP-321 prefill, memo) and
/// `SwapAndPay` drives swap mode (asset list, quote, slippage). `Mode` decides which one the single
/// screen is bound to, so there is exactly one user-facing form.
///
/// **Transaction-guard discipline.** Neither mode broadcasts here. ZEC-direct submits through the
/// `sendConfirmation` path element and swap submits through the `sending` path element — both are
/// `SendConfirmation`, whose `sendTriggered` / `createTransactionFromPCZT` cases make the *only*
/// calls into the guarded `sdkSynchronizer` closures. No call site in this file acquires the guard,
/// and no code path here calls two guarded closures in sequence (see `AGENTS.md` on
/// `Dependencies/TransactionGuard/`).
///
/// Swap-to-ZEC (deposit an external asset to receive ZEC) and cross-pay are *not* part of Android's
/// unified screen; they stay in `SwapAndPayCoordFlow` and are reached from this form's
/// deposit affordance (`swapToZecRequested`) so that corridor is not orphaned.
@Reducer
struct SendCoordFlow {
    /// Which form the single unified screen is currently showing. Android derives the equivalent
    /// from the selected asset's type; iOS keeps it explicit because `SwapAndPay` pre-selects a
    /// non-ZEC asset of its own accord (for its asset list), which must not silently flip the
    /// screen into swap mode.
    enum Mode: Equatable {
        case zec
        case swap
    }

    /// Android's `PrimaryButtonState`.
    enum PrimaryButton: Equatable {
        case review
        case topUp
        /// An empty wallet's form is replaced by the Add funds panel; this opens the same Top Up
        /// picker as `.topUp`.
        case addZec
        case disabled
    }

    @Reducer
    enum Path {
        case addressBook(AddressBook)
        case addressDetails(AddressDetails)
        case addressBookContact(AddressBook)
        case confirmWithKeystone(SendConfirmation)
        case keystoneFirmwareUpdate(SendConfirmation)
        case preSendingFailure(SendConfirmation)
        case requestZecConfirmation(SendConfirmation)
        case scan(Scan)
        case sendConfirmation(SendConfirmation)
        case sending(SendConfirmation)
        case sendResultFailure(SendConfirmation)
        case sendResultPending(SendConfirmation)
        case sendResultSuccess(SendConfirmation)
        case transactionDetails(TransactionDetails)
    }

    @ObservableState
    struct State {
        var path = StackState<Path.State>()
        var sendFormState = SendForm.State.initial
        var swapState = SwapAndPay.State.initial
        @Shared(.inMemory(.selectedWalletAccount)) var selectedWalletAccount: WalletAccount? = nil
        @Shared(.inMemory(.transactions)) var transactions: IdentifiedArrayOf<TransactionState> = []
        @Shared(.inMemory(.walletFunding)) var walletFunding: WalletFunding = .unknown

        var mode: Mode = .zec
        var isAssetPickerPresented = false
        /// Android's `TopUpArgs` sheet, raised by the "Top Up" CTA. See `SendCoordFlow+TopUp`.
        var isTopUpPresented = false
        /// Opened from the Pay tab's Swap action. Android's FAB opens a screen titled "Swap"; this
        /// form keeps that title while it is in swap mode.
        var isSwapEntry = false
        /// Which of the two amount inputs leads. Android keeps one field plus an "≈" line and a
        /// swap affordance; this is that affordance's state for ZEC-direct mode (swap mode uses
        /// `SwapAndPay.State.isInputInUsd`).
        var isFiatPrimary = false
        /// Android's `UnifiedSendArgs.isScanZip321Enabled`. "Send again" opens the form with it
        /// off, so scanning from inside the form can only pick up a plain address.
        var isScanZip321Enabled = true

        var isSwap: Bool { mode == .swap }

        /// Android's `hasZeroBalance` (`account.spendableShieldedBalance == 0`).
        var hasZeroBalance: Bool {
            sendFormState.walletBalancesState.shieldedBalance.amount == 0
        }

        var isInsufficientFunds: Bool {
            mode == .zec ? sendFormState.isInsufficientFunds : swapState.isInsufficientFunds
        }

        /// A swap submission is already on the path. The quote sheet's Confirm can deliver a second
        /// tap while the sheet animates away, and in swap mode that tap is what pushes the element
        /// that broadcasts — so without this, two taps push two submissions of the *same* proposal.
        /// The transaction guard is a FIFO mutex: it would serialise them rather than reject the
        /// duplicate, so the second broadcast fails on already-spent notes and lands a failure
        /// screen on top of a send that had already succeeded. ZEC-direct mode has the equivalent
        /// protection in `SendConfirmation` (its CTA disables itself via `isSending`).
        var isSwapSubmissionInFlight: Bool {
            path.contains { $0.is(\.sending) || $0.is(\.confirmWithKeystone) }
        }

        /// Android's `UnifiedSendState.addFundsPanel`: a synced, empty wallet sees "Add ZEC" in
        /// place of the form, for Send and for Swap (this form only swaps ZEC out). Swap-in stays
        /// reachable through the deposit row, so an empty wallet can still bring another asset in.
        var showsAddFundsPanel: Bool {
            walletFunding == .empty
        }

        /// Android's `buildPrimaryButton`: zero balance in ZEC mode, or insufficient funds in
        /// either mode, replaces Review with Top Up; an empty wallet's panel offers Add ZEC.
        var primaryButton: PrimaryButton {
            if showsAddFundsPanel {
                return .addZec
            }
            if mode == .zec && hasZeroBalance {
                return .topUp
            }
            if isInsufficientFunds {
                return .topUp
            }
            switch mode {
            case .zec:
                return sendFormState.isValidForm ? .review : .disabled
            case .swap:
                return (swapState.isValidForm && !swapState.isQuoteRequestInFlight) ? .review : .disabled
            }
        }

        /// Android's `infoFooter` — the Top-Up explainer, ZEC-direct mode only.
        var isTopUpFooterVisible: Bool {
            mode == .zec && (hasZeroBalance || isInsufficientFunds)
        }

        /// The asset shown in the selector. `nil` in swap mode only while the asset list loads.
        var selectedSwapAsset: SwapAsset? {
            mode == .zec ? nil : swapState.selectedAsset
        }

        init() { }
    }

    enum Action {
        /// Android's `onAmountSwap` — flips which of ZEC / local currency leads the amount field.
        case amountInputSwapped
        case assetPickerDismissed
        case assetPickerRequested
        case backButtonTapped
        case backToHomeTapped
        case path(StackActionOf<Path>)
        case resolveSendResult(SendConfirmation.State.Result?, SendConfirmation.State)
        case sendForm(SendForm.Action)
        case swap(SwapAndPay.Action)
        case swapAssetSelected(SwapAsset)
        /// The app-lock check for a swap passed; the sending screen may be pushed.
        case swapSendAuthorized
        /// Delegate to Root: hand off to `SwapAndPayCoordFlow`'s swap-to-ZEC corridor, which the
        /// unified screen deliberately does not cover (Android's unified screen doesn't either).
        case swapToZecRequested
        /// Android's `TopUpArgs`: the source picker over the form (`SendCoordFlow+TopUp`).
        case topUpRequested
        case topUpDismissed
        case topUpSourcePicked(TopUpSource)
        case topUpUnifiedAddressResolved(String?)
        case viewTransactionRequested(SendConfirmation.State)
        case zecAssetSelected
    }

    @Dependency(\.audioServices) var audioServices
    @Dependency(\.keystoneHandler) var keystoneHandler
    @Dependency(\.localAuthentication) var localAuthentication
    @Dependency(\.numberFormatter) var numberFormatter
    @Dependency(\.sdkSynchronizer) var sdkSynchronizer
    @Dependency(\.swapAndPay) var swapAndPay
    @Dependency(\.userMetadataProvider) var userMetadataProvider

    init() { }

    var body: some Reducer<State, Action> {
        coordinatorReduce()

        topUpReduce()

        Scope(state: \.sendFormState, action: \.sendForm) {
            SendForm()
        }

        Scope(state: \.swapState, action: \.swap) {
            SwapAndPay()
        }

        Reduce { state, action in
            switch action {
            default: return .none
            }
        }
        .forEach(\.path, action: \.path)
    }
}
