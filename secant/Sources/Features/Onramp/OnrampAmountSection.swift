//
//  OnrampAmountSection.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI

/// The amount step and its confirmation, mirroring Android's `OnrampAmountSection.kt`.
extension OnrampView {
    enum Constants {
        /// Matched to `ZappButton`'s 52pt so the destination row stands level with the controls
        /// above and below it instead of reading as a thin strip between them.
        static let destinationCellHeight: CGFloat = 46
    }

    /// Ordered as Android's `AmountContent`: say what this is, take the amount, then qualify it.
    /// The account address is deliberately absent — it lives behind the header's info button
    /// (`infoAccountBlock`), because it is reference material, not part of choosing an amount.
    var amount: some View {
        VStack(alignment: .leading, spacing: 18) {
            intro

            ZappAmountHero(
                label: String(localizable: .onrampAmountLabel),
                symbol: store.currencySymbol,
                amount: store.amount,
                balance: heroBalance,
                isEnabled: !store.isRequestingQuote,
                onChange: { value in
                    MainActor.assumeIsolated {
                        _ = store.send(.amountChanged(value))
                    }
                }
            )

            if store.isZecDestinationEnabled {
                destinationSelector
            }

            ZappBorderedCard {
                VStack(spacing: 10) {
                    if let limits = limitsText {
                        ZappSummaryRow(label: String(localizable: .onrampLimitsLabel), value: limits)
                    }
                    ZappSummaryRow(label: String(localizable: .onrampDailyLimitLabel), value: dailyLimitText)
                    ZappSummaryRow(label: String(localizable: .onrampPaymentRailLabel), value: store.paymentRail)
                }
            }

            sendToZecAction
            errorText

            Text(String(localizable: .onrampQuoteDisclaimer))
                .zappFont(.caption, style: ZappColors.textMuted)
        }
    }

    var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localizable: .onrampEyebrow).uppercased())
                .zappFont(.caption, style: ZappColors.accent)
            Text(String(localizable: .onrampHeadline))
                .zappFont(.screenTitle, style: ZappColors.text)
            Text(store.destination == .zcash
                 ? String(localizable: .onrampZcashSubtitle)
                 : String(localizable: .onrampSubtitle))
                .zappFont(.body, style: ZappColors.textMuted)
        }
    }

    /// Marks beside the labels, as Android's `DestinationSelector` has them: the choice is between
    /// two tokens, and the logos read faster than the words.
    var destinationSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localizable: .onrampDestinationLabel))
                .zappFont(.caption, style: ZappColors.textMuted)
            ZappSegmentedSelector(
                options: [
                    String(localizable: .onrampDestinationZcash),
                    String(localizable: .onrampDestinationBase)
                ],
                icons: [0: Asset.Assets.Assets.zec.image, 1: Asset.Assets.Assets.usdc.image],
                cellMinHeight: Constants.destinationCellHeight,
                selectedIndex: store.destination == .zcash ? 0 : 1
            ) { index in
                store.send(.destinationSelected(index == 0 ? .zcash : .base))
            }
        }
    }

    /// The balance rides the amount field, where Android puts it: it is the number the amount is
    /// measured against, not a card of its own.
    var heroBalance: ZappFieldBalance? {
        guard let balance = store.baseBalance else { return nil }
        return ZappFieldBalance(
            label: String(localizable: .onrampBaseBalanceLabel),
            amount: String(localizable: .peerUsdcAmount(balance))
        )
    }

    /// Trailing-aligned and compact, as on Android: an escape hatch for funds already sitting on
    /// Base, not a second call to action competing with the dock's primary.
    @ViewBuilder
    var sendToZecAction: some View {
        if store.baseBalance != nil, store.baseRefundState != .hidden {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    // Accent-outlined rather than a plain ghost: it moves real money, so it should
                    // read as an action. Not a filled primary — that is the dock's.
                    ZappCompactButton(
                        title: store.baseRefundState == .inProgress
                            ? String(localizable: .onrampSendToZecInProgress)
                            : String(localizable: .onrampSendToZec),
                        variant: .accentGhost,
                        isEnabled: store.baseRefundState == .available || store.baseRefundState == .failedRetry
                    ) { store.send(.sendBaseBalanceToZecTapped) }
                }

                if store.baseRefundState == .blocked {
                    Text(String(localizable: .offrampHistoryRefundBlocked))
                        .zappFont(.caption, style: ZappColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    var confirmation: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localizable: .onrampConfirmTitle))
                .zappFont(.screenTitle, style: ZappColors.text)

            if let quote = store.quote {
                ZappCompactLedger(rows: [
                    .init(
                        label: String(localizable: .onrampYouPayLabel),
                        value: "\(store.currencySymbol)\(Onramp.displayMicros(quote.fiatMicros))"
                    ),
                    .init(
                        label: String(localizable: .onrampYouReceiveLabel),
                        value: receiveQuoteText(quote)
                    ),
                    .init(
                        label: String(localizable: .onrampFeeLabel),
                        value: "\(Onramp.displayMicros(quote.feeUsdcMicros)) USDC"
                    ),
                    .init(
                        label: String(localizable: .onrampRateLabel),
                        value: "\(store.currencySymbol)\(Onramp.displayMicros(quote.buyPriceMicros)) / USDC"
                    )
                ])
            }

            if store.destination == .zcash {
                ZappBorderedCard {
                    if store.isRequestingZecEstimate {
                        HStack(spacing: 10) {
                            ProgressView().tint(ZappColors.accent.color(colorScheme))
                            Text(String(localizable: .onrampZecEstimateLoading))
                                .zappFont(.body, style: ZappColors.textMuted)
                        }
                    } else if let estimate = store.zecEstimate {
                        VStack(spacing: 10) {
                            ZappSummaryRow(
                                label: String(localizable: .onrampReceiveZecAfterSettlement),
                                value: "\(estimate.outputZec) ZEC"
                            )
                            ZappSummaryRow(
                                label: String(localizable: .onrampEstimatedConversionCostLabel),
                                value: "\(Self.percent(estimate.costBasisPoints))%"
                            )
                        }
                    }
                }
            }

            if let seconds = store.quoteSecondsRemaining {
                ZappSummaryRow(
                    label: String(localizable: .onrampQuoteExpiresInLabel),
                    value: duration(seconds)
                )
            }
            Text(String(localizable: .onrampQuoteRefreshNotice))
                .zappFont(.caption, style: ZappColors.textMuted)
            errorText
        }
    }

    var limitsText: String? {
        guard let limits = store.limits else { return nil }
        let minimum = Onramp.displayMicros(limits.minimumFiatMicros)
        let maximum = Onramp.displayMicros(limits.maximumFiatMicros)
        return "\(store.currencySymbol)\(minimum)–\(store.currencySymbol)\(maximum)"
    }

    var dailyLimitText: String {
        guard let value = store.limits?.dailyFiatMicros else { return String(localizable: .onrampBaseBalanceUnavailable) }
        return "\(store.currencySymbol)\(Onramp.displayMicros(value))"
    }

    func receiveQuoteText(_ quote: OnrampQuoteModel) -> String {
        if store.destination == .zcash {
            return store.zecEstimate.map { "\($0.outputZec) ZEC" } ?? String(localizable: .onrampZecEstimateLoading)
        }
        return "\(Onramp.displayMicros(quote.netUsdcMicros)) USDC"
    }
}
