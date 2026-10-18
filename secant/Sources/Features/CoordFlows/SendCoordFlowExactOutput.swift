//
//  SendCoordFlowExactOutput.swift
//  Zapp
//
//  Exact-output swaps on the unified send form ("They receive exactly"), iOS's counterpart to the
//  `swapMode` half of Android's `UnifiedSendVM` / `UnifiedSendVMMapper`.
//
//  Which side the user last typed into is the single source of truth, and it lives in
//  `SwapAndPay.State.isSwapExperienceEnabled` (false = EXACT_OUTPUT), the flag the quote sheet, the
//  slippage copy, the result screens and the swap history already branch on. Typing the destination
//  amount pins the quote to that side; tapping the pay side's "≈ X ZEC" estimate is the only way back.
//
//  While exact-output is in force, `SwapAndPay.State.amountText` carries the destination amount in
//  token units (its legacy CrossPay meaning) and `isInputInUsd` is false. The amount actually requested
//  is handed over as exact base units in `exactOutputBaseUnits`, re-derived when the quote is asked
//  for, so it always matches the asset selected at that moment.
//

import Foundation
import ComposableArchitecture
@preconcurrency import ZcashLightClientKit

extension SendCoordFlow.State {
    /// Android's `isExactOutput` (`mode == EXACT_OUTPUT`, swap mode only).
    var isExactOutput: Bool {
        mode == .swap && !swapState.isSwapExperienceEnabled && !swapState.isSwapToZecExperienceEnabled
    }

    /// The destination amount NEAR is asked to deliver, in the asset's own units. Nil while there is
    /// no usable figure — including a typed amount finer than the asset can settle, which disables
    /// Review rather than silently requesting less than the field shows.
    var destinationTokenAmount: Decimal? {
        guard isExactOutput, let asset = swapState.selectedAsset, let typed = destinationTypedAmount, typed > 0 else {
            return nil
        }
        if isDestinationTypedInUsd {
            guard let token = ExactOutputSwap.divide(typed, by: asset.usdPrice) else { return nil }
            let truncated = ExactOutputSwap.truncated(token, decimals: asset.decimals)
            return truncated > 0 ? truncated : nil
        }
        return ExactOutputSwap.exceedsDecimals(typed, decimals: asset.decimals) ? nil : typed
    }

    /// Android's exact-output `zecValue`: what the destination amount should cost, from USD prices.
    /// Deliberately un-padded, as Android does — a user close to their ceiling passes here and is
    /// caught by the proposal's insufficient-balance error once the real quote lands.
    var exactOutputZecEstimate: Decimal? {
        guard let asset = swapState.selectedAsset, let zecAsset = swapState.zecAsset else { return nil }
        return ExactOutputSwap.estimateZec(
            token: destinationTokenAmount,
            tokenUsdPrice: asset.usdPrice,
            zecUsdPrice: zecAsset.usdPrice
        )
    }

    /// Android's `!hasFunds` in exact-output.
    var isExactOutputInsufficientFunds: Bool {
        guard let estimate = exactOutputZecEstimate else { return false }
        let spendable = Decimal(swapState.walletBalancesState.shieldedBalance.amount) / Decimal(Zatoshi.Constants.oneZecInZatoshi)
        return estimate > spendable
    }

    /// Android's `isAddressValid && isAmountValid` for exact-output.
    var isExactOutputFormValid: Bool {
        swapState.selectedAsset != nil
            && !swapState.address.isEmpty
            && destinationTokenAmount != nil
            && !isExactOutputInsufficientFunds
    }

    /// Whether the destination field can flip to USD: not without a price to convert with.
    var canSwapDestinationCurrency: Bool {
        (swapState.selectedAsset?.usdPrice ?? 0) > 0
    }

    /// Whether the destination field is showing USD right now.
    var isDestinationShownInUsd: Bool {
        isDestinationInUsd && canSwapDestinationCurrency
    }

    /// The "They receive ≈" estimate in exact-input: what the typed pay amount buys, truncated to the
    /// asset's precision.
    func exactInputDestinationEstimate(locale: Locale) -> Decimal? {
        guard
            let asset = swapState.selectedAsset,
            let zecAsset = swapState.zecAsset,
            let typed = ExactOutputSwap.decimal(from: swapState.amountText, locale: locale)
        else {
            return nil
        }
        let zec = swapState.isInputInUsd ? ExactOutputSwap.divide(typed, by: zecAsset.usdPrice) : typed
        return ExactOutputSwap.estimateToken(zec: zec, zecUsdPrice: zecAsset.usdPrice, tokenUsdPrice: asset.usdPrice)
            .map { ExactOutputSwap.truncated($0, decimals: asset.decimals) }
    }

    /// The figure the destination field shows: what the user typed, the same amount in the other
    /// currency after a flip, or (exact-input) the estimate.
    func destinationFieldText(locale: Locale) -> String {
        guard let asset = swapState.selectedAsset else { return "" }
        let tokenDigits = min(asset.decimals, ExactOutputSwap.maxDisplayFractionDigits)
        if isExactOutput {
            if isDestinationTypedInUsd == isDestinationShownInUsd {
                return destinationText
            }
            guard let token = destinationTokenAmount else { return "" }
            if isDestinationShownInUsd {
                return ExactOutputSwap.usd(token, price: asset.usdPrice)
                    .map { ExactOutputSwap.display($0, maxFractionDigits: ExactOutputSwap.usdFractionDigits, locale: locale) } ?? ""
            }
            return ExactOutputSwap.display(token, maxFractionDigits: tokenDigits, locale: locale)
        }
        guard let estimate = exactInputDestinationEstimate(locale: locale), estimate > 0 else { return "" }
        if isDestinationShownInUsd {
            return ExactOutputSwap.usd(estimate, price: asset.usdPrice)
                .map { ExactOutputSwap.display($0, maxFractionDigits: ExactOutputSwap.usdFractionDigits, locale: locale) } ?? ""
        }
        return ExactOutputSwap.display(estimate, maxFractionDigits: tokenDigits, locale: locale)
    }

    /// The unit printed after the destination field (Android's `TheyReceiveState.unit`).
    var destinationUnit: String {
        isDestinationShownInUsd ? CurrencyISO4217.usd.code : (swapState.selectedAsset?.token ?? "")
    }

    /// The figure in the pay side's "≈ X ZEC" row, or nil when prices have not loaded (the row then
    /// says the cost is unknown rather than disappearing — the payment still works, NEAR prices it).
    func exactOutputZecEstimateText(locale: Locale) -> String? {
        exactOutputZecEstimate.map {
            ExactOutputSwap.display($0, maxFractionDigits: ExactOutputSwap.maxDisplayFractionDigits, locale: locale)
        }
    }
}

extension SendCoordFlow {
    func exactOutputReduce() -> Reduce<SendCoordFlow.State, SendCoordFlow.Action> {
        Reduce { state, action in
            switch action {
            case .crossPayInfoTapped:
                guard state.mode == .swap else { return .none }
                state.isCrossPayInfoPresented = true
                return .none

            case .crossPayInfoDismissed:
                state.isCrossPayInfoPresented = false
                return .none

                // Android's `onTokenAmountChange` / `onTokenFiatAmountChange`. Touching the
                // destination pins the quote to it and keeps it pinned: emptying the field leaves the
                // payment exact-output with no amount yet, so Review simply disables.
            case .destinationAmountChanged(let text):
                guard state.mode == .swap, !state.swapState.isQuoteRequestInFlight else { return .none }
                // Not a number (e.g. "0.10.5"): kept, with no amount, so Review disables. Android's
                // field drops the keystroke, but a SwiftUI TextField keeps showing it, and a dropped
                // edit would leave the last valid figure requested under text that says otherwise.
                let typed = ExactOutputSwap.decimal(from: text, locale: locale)
                if !state.isExactOutput {
                    // Nothing typed yet: the estimate stays an estimate.
                    guard !text.isEmpty else { return .none }
                    state.isPayInUsdBeforeExactOutput = state.swapState.isInputInUsd
                    state.swapState.isSwapExperienceEnabled = false
                    state.swapState.isInputInUsd = false
                }
                state.destinationText = text
                state.destinationTypedAmount = typed
                state.isDestinationTypedInUsd = state.isDestinationShownInUsd
                Self.syncExactOutputAmount(&state, locale: locale)
                return .none

            case .destinationCurrencySwapped:
                guard state.mode == .swap, state.canSwapDestinationCurrency, !state.swapState.isQuoteRequestInFlight else {
                    return .none
                }
                state.isDestinationInUsd.toggle()
                return .none

                // Android's `onPayEstimateClick`: hands authority back to the pay side, carrying the ZEC
                // estimate over so the amount survives the switch.
            case .payEstimateTapped:
                guard state.isExactOutput, !state.swapState.isQuoteRequestInFlight else { return .none }
                let estimate = state.exactOutputZecEstimate
                Self.resetExactOutput(&state)
                guard let estimate, estimate > 0 else { return .none }
                if state.swapState.isInputInUsd {
                    let usd = state.swapState.zecAsset.flatMap { ExactOutputSwap.usd(estimate, price: $0.usdPrice) }
                    state.swapState.amountText = usd.map {
                        ExactOutputSwap.display($0, maxFractionDigits: ExactOutputSwap.usdFractionDigits, locale: locale)
                    } ?? ""
                } else {
                    state.swapState.amountText = ExactOutputSwap.display(
                        estimate,
                        maxFractionDigits: ExactOutputSwap.maxDisplayFractionDigits,
                        locale: locale
                    )
                }
                return .none

                // Re-derive the requested base units against the asset selected *now* (a contact pick
                // can change it after the amount was typed). Runs before `SwapAndPay` sees the action;
                // without a usable amount the quote request is starved of its amount and builds nothing.
            case .swap(.getQuoteTapped), .swap(.getQuote):
                guard state.isExactOutput else {
                    state.swapState.exactOutputBaseUnits = nil
                    return .none
                }
                Self.syncExactOutputAmount(&state, locale: locale)
                return .none

            default:
                return .none
            }
        }
    }

    /// Mirrors the destination amount into `SwapAndPay`: `amountText` in token units (read by the
    /// slippage sheet's USD figure and the legacy validity checks) and the exact base units to request.
    static func syncExactOutputAmount(_ state: inout State, locale: Locale) {
        guard let asset = state.swapState.selectedAsset, let token = state.destinationTokenAmount else {
            state.swapState.amountText = ""
            state.swapState.exactOutputBaseUnits = nil
            return
        }
        state.swapState.amountText = ExactOutputSwap.display(token, maxFractionDigits: asset.decimals, locale: locale)
        state.swapState.exactOutputBaseUnits = ExactOutputSwap.baseUnits(token, decimals: asset.decimals)
    }

    /// Android's `clearTokenAmount`: back to exact-input with no destination amount. A pay amount is
    /// not carried over — in exact-output `amountText` held a token figure, never ZEC.
    static func resetExactOutput(_ state: inout State) {
        if state.isExactOutput {
            state.swapState.isSwapExperienceEnabled = true
            state.swapState.isInputInUsd = state.isPayInUsdBeforeExactOutput
            state.swapState.amountText = ""
        }
        state.destinationText = ""
        state.destinationTypedAmount = nil
        state.isDestinationTypedInUsd = false
        state.swapState.exactOutputBaseUnits = nil
        state.swapState.exactOutputRequest = nil
    }
}
