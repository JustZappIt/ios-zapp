//
//  ZappBalanceCard.swift
//  Zapp
//
//  The Pay tab hero, mirroring Android's `WalletBalanceCard.kt`.
//

import ComposableArchitecture
import SwiftUI
@preconcurrency import ZcashLightClientKit

struct ZappBalanceCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Dependency(\.date) private var date
    @Dependency(\.userStoredPreferences) private var userStoredPreferences

    private enum Constants {
        static let horizontalPadding: CGFloat = 20
        static let verticalPadding: CGFloat = 18
        static let dotSize: CGFloat = 8
        static let chevronGap: CGFloat = 6
        /// Lifts the 14pt label to the 44pt HIG target without moving anything around it — the
        /// same trick Android plays by folding the card's leading padding into the row.
        static let labelHitSlop: CGFloat = 15
        static let heroMinimumScale: CGFloat = 22 / 52

        static let hero = ZappTextStyle(weight: .black, size: 52, lineHeight: 52, tracking: -3)
        static let heroFraction = ZappTextStyle(weight: .bold, size: 26, lineHeight: 32, tracking: -1)
        static let ticker = ZappTextStyle(weight: .light, size: 22, lineHeight: 28)
    }

    @Shared(.appStorage(.sensitiveContent)) var isSensitiveContentHidden = false
    @Shared(.inMemory(.exchangeRate)) var currencyConversion: CurrencyConversion? = nil
    @Shared(.inMemory(.zappFiatQuote)) var zappFiatQuote: ZappFiatQuote? = nil

    let totalBalance: Zatoshi
    let confirmedBalance: Zatoshi
    let shieldedBalance: Zatoshi
    let transparentBalance: Zatoshi
    let showsBreakdown: Bool
    let canShield: Bool
    let tokenName: String
    let transactions: [TransactionState]
    let showZecAsPrimary: Bool
    let onBalanceTapped: () -> Void
    let onToggleBalanceDisplay: () -> Void
    let onShieldTapped: () -> Void

    var body: some View {
        WithPerceptionTracking {
            VStack(alignment: .leading, spacing: 0) {
                sectionLabel
                    .padding(.bottom, 8)

                amount

                // Removed, not redacted, while balances are masked: the chart leaks exact values
                // three ways — the delta row, the scrub readout, and the VoiceOver value — and the
                // balance text switches to masked values under the same shared preference.
                if totalBalance.amount > 0, !isSensitiveContentHidden {
                    ZappBalanceChart(
                        transactions: transactions,
                        confirmedBalance: confirmedBalance,
                        tokenName: tokenName
                    )
                        .padding(.top, 10)
                }

                if showsBreakdown {
                    breakdown
                        .padding(.top, 20)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Constants.horizontalPadding)
            .padding(.vertical, Constants.verticalPadding)
        }
    }

    /// The label doubles as the entry point to the per-pool breakdown, as it does on Android
    /// (`WalletBalanceCard.kt:161`). The balance figure already owns a tap — it flips ZEC/fiat — so
    /// the sheet hangs off the label rather than stealing that gesture.
    private var sectionLabel: some View {
        Button(action: onBalanceTapped) {
            HStack(spacing: Constants.chevronGap) {
                ZappSectionLabel(text: String(localizable: .zappPayTotalBalance))

                // A glyph, not a word: the chevron is Android's `BasicText("›")` verbatim.
                Text(verbatim: "›")
                    .zappFont(.groupLabel, style: ZappColors.textSubtle)
            }
            .padding(.vertical, Constants.labelHitSlop)
            .contentShape(Rectangle())
            .padding(.vertical, -Constants.labelHitSlop)
        }
        // Android passes `indication = null` on both this row and the amount below it.
        .buttonStyle(.plain)
        .accessibilityLabel(String(localizable: .zappPayBalancePoolsAccessibility))
        .accessibilityIdentifier(PoolBalancesSheet.Accessibility.openButton)
    }

    private var amount: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                currencyButton { primaryAmount }

                if fiat == nil {
                    visibilityButton
                }
            }

            if let fiat {
                HStack(spacing: 0) {
                    currencyButton {
                        scrambledText(
                            showZecAsPrimary ? "\(fiat.whole)\(fiat.fraction)" : "\(zecText) \(tokenName)",
                            hidden: showZecAsPrimary ? hiddenBalance : "\(hiddenBalance) \(tokenName)"
                        )
                        .zappFont(.caption, style: ZappColors.textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    }
                    visibilityButton
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func currencyButton<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if fiat != nil {
            Button(action: onToggleBalanceDisplay) {
                content().contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            content()
        }
    }

    private var visibilityButton: some View {
        ZappInputFieldAction(
            icon: isSensitiveContentHidden ? Asset.Assets.eyeOff.image : Asset.Assets.eyeOn.image,
            accessibilityLabel: String(localizable: isSensitiveContentHidden ? .zappPayShowBalances : .zappPayHideBalances)
        ) {
            $isSensitiveContentHidden.withLock { $0.toggle() }
        }
        .accessibilityIdentifier("pay.balanceVisibility")
    }

    @ViewBuilder private var primaryAmount: some View {
        if let fiat, !showZecAsPrimary {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                scrambledText(fiat.whole)
                    .zappFont(Constants.hero, style: ZappColors.text)

                scrambledText(fiat.fraction, hidden: "")
                    .zappFont(Constants.heroFraction, style: ZappColors.textMuted)
            }
            .lineLimit(1)
            .minimumScaleFactor(Constants.heroMinimumScale)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                scrambledText(zecText)
                    .zappFont(Constants.hero, style: ZappColors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(Constants.heroMinimumScale)

                Text(tokenName)
                    .zappFont(Constants.ticker, style: ZappColors.textMuted)
            }
        }
    }

    private var hiddenBalance: String { String(localizable: .generalHideBalancesMost) }

    private func scrambledText(_ clear: String, hidden: String? = nil) -> some View {
        ZappScrambledBalanceText(
            clearText: clear,
            hiddenText: hidden ?? hiddenBalance,
            isHidden: isSensitiveContentHidden
        )
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(ZappColors.border.color(colorScheme))
                .frame(height: 1)
                .padding(.bottom, 14)

            breakdownLine(
                label: String(localizable: .zappPayShielded),
                amount: hidable("\(shieldedBalance.decimalString()) \(tokenName)"),
                dotColor: .accent
            )
            .padding(.bottom, 8)

            breakdownLine(
                label: String(localizable: .zappPayTransparent),
                amount: hidable("\(transparentBalance.decimalString()) \(tokenName)"),
                dotColor: .textSubtle
            )

            if canShield {
                ZappButton(title: String(localizable: .zappPayShield), action: onShieldTapped)
                    .padding(.top, 14)
            }
        }
    }

    private func breakdownLine(label: String, amount: String, dotColor: ZappColors) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(dotColor.color(colorScheme))
                .frame(width: Constants.dotSize, height: Constants.dotSize)

            Text(label)
                .zappFont(.body, style: ZappColors.textMuted)

            Spacer(minLength: 8)

            Text(amount)
                .zappFont(.rowTitle, style: ZappColors.text)
                .lineLimit(1)
        }
    }

    private var zecText: String {
        totalBalance.decimalString()
    }

    private var fiat: (whole: String, fraction: String)? {
        guard let conversion = ZappFiatRate.resolve(
            preference: userStoredPreferences.exchangeRate(),
            conversion: currencyConversion,
            fallback: zappFiatQuote,
            at: date.now()
        ) else {
            return nil
        }

        let formatted: String = conversion.convert(totalBalance)
        guard !formatted.isEmpty else { return nil }

        let separator = Locale.current.decimalSeparator ?? "."
        guard let range = formatted.range(of: separator, options: .backwards) else {
            return (formatted, "")
        }

        return (String(formatted[formatted.startIndex..<range.lowerBound]), String(formatted[range.lowerBound...]))
    }

    private func hidable(_ value: String) -> String {
        isSensitiveContentHidden ? String(localizable: .generalHideBalancesMost) : value
    }
}
