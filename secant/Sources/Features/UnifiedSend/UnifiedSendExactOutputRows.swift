//
//  UnifiedSendExactOutputRows.swift
//  Zapp
//
//  The two rows of the unified send form that exact-output swaps change: the destination amount
//  (Android's `SendDestinationRow.kt`) and the pay side's estimate (Android's `PayEstimateRow` in
//  `UnifiedSendView.kt`). State and arithmetic live in `SendCoordFlowExactOutput.swift`.
//

import SwiftUI
import ComposableArchitecture

/// One field carrying the destination amount in the token or in USD. Typing in it makes the payment
/// exact-output ("They receive exactly"); in exact-input it carries the estimate, which turns into the
/// placeholder on focus so the first keystroke replaces a figure the user never entered.
struct UnifiedSendDestinationRow: View {
    private enum Constants {
        static let fieldHeight: CGFloat = 40
        static let convertButtonSize: CGFloat = 36
        static let convertIconSize: CGFloat = 16
    }

    @Environment(\.colorScheme) private var colorScheme

    let store: StoreOf<SendCoordFlow>
    let placeholder: String
    let isDisabled: Bool
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        WithPerceptionTracking {
            HStack(spacing: Design.Spacing._md) {
                Text(label)
                    .zappFont(.caption, style: ZappColors.text)

                TextField("", text: text, prompt: prompt)
                    .zappFont(.caption, style: ZappColors.text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused(isFocused)
                    .disabled(isDisabled)
                    .accessibilityLabel(label)

                Text(store.destinationUnit)
                    .zappFont(.caption, style: ZappColors.textMuted)

                if store.canSwapDestinationCurrency {
                    Button {
                        store.send(.destinationCurrencySwapped)
                    } label: {
                        Asset.Assets.Icons.switchHorizontal.image
                            .zImage(width: Constants.convertIconSize, height: Constants.convertIconSize, style: ZappColors.textMuted)
                            .rotationEffect(.degrees(90))
                            .frame(width: Constants.convertButtonSize, height: Constants.convertButtonSize)
                    }
                    .buttonStyle(.zappPress)
                    .disabled(isDisabled)
                    .accessibilityLabel(String(localizable: .unifiedSendSwapAmounts))
                }
            }
            .padding(.leading, Design.Spacing._md)
            .frame(minHeight: Constants.fieldHeight)
            .background(ZappColors.surfaceInput.color(colorScheme))
            .overlay(
                Rectangle()
                    .strokeBorder(
                        store.isExactOutput && store.isInsufficientFunds ? ZappColors.danger.color(colorScheme) : Color.clear,
                        lineWidth: 1
                    )
            )
            .zappFieldTapTarget(isFocused)
        }
    }

    private var label: String {
        store.isExactOutput
            ? String(localizable: .unifiedSendTheyReceiveExact)
            : String(localizable: .unifiedSendTheyReceiveApproxLabel)
    }

    private var text: Binding<String> {
        Binding(
            get: {
                if !store.isExactOutput && isFocused.wrappedValue {
                    return ""
                }
                return store.state.destinationFieldText(locale: .current)
            },
            set: { store.send(.destinationAmountChanged($0)) }
        )
    }

    private var prompt: Text {
        let estimate = store.isExactOutput ? "" : store.state.destinationFieldText(locale: .current)
        return Text(estimate.isEmpty ? placeholder : estimate)
            .foregroundColor(ZappColors.textSubtle.color(colorScheme))
    }
}

/// The muted "≈ 0.42 ZEC" standing in for the pay field while exact-output is in force: what is
/// actually spent is only known once NEAR quotes it. Tapping it hands authority back to the pay side.
struct UnifiedSendPayEstimateRow: View {
    private enum Constants {
        static let fieldHeight: CGFloat = 40
        /// Prices have not loaded: say the cost is unknown rather than dropping the row (Android).
        static let unknownAmount = "—"
    }

    @Environment(\.colorScheme) private var colorScheme

    let store: StoreOf<SendCoordFlow>
    let tokenName: String
    let errorText: String?
    let isDisabled: Bool
    let onTap: () -> Void

    var body: some View {
        WithPerceptionTracking {
            VStack(alignment: .leading, spacing: Design.Spacing._xs) {
                Button {
                    onTap()
                    store.send(.payEstimateTapped)
                } label: {
                    Text(
                        String(
                            localizable: .unifiedSendEstimatedEquivalent(
                                store.state.exactOutputZecEstimateText(locale: .current) ?? Constants.unknownAmount,
                                tokenName.uppercased()
                            )
                        )
                    )
                    .zappFont(.rowTitle, style: ZappColors.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Design.Spacing._md)
                    .frame(minHeight: Constants.fieldHeight)
                    .background(ZappColors.surfaceInput.color(colorScheme))
                    .overlay(
                        Rectangle()
                            .strokeBorder(
                                store.isInsufficientFunds ? ZappColors.danger.color(colorScheme) : Color.clear,
                                lineWidth: 1
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.zappPress)
                .disabled(isDisabled)

                if let errorText {
                    Text(errorText)
                        .zappFont(.caption, style: ZappColors.danger)
                }
            }
        }
    }
}
