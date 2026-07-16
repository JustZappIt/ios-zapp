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

    private enum Constants {
        static let horizontalPadding: CGFloat = 20
        static let verticalPadding: CGFloat = 18
        static let dotSize: CGFloat = 8
        static let heroMinimumScale: CGFloat = 22 / 52

        static let hero = ZappTextStyle(weight: .black, size: 52, lineHeight: 52, tracking: -3)
        static let heroFraction = ZappTextStyle(weight: .bold, size: 26, lineHeight: 32, tracking: -1)
        static let ticker = ZappTextStyle(weight: .light, size: 22, lineHeight: 28)
    }

    @Shared(.appStorage(.sensitiveContent)) var isSensitiveContentHidden = false
    @Shared(.inMemory(.exchangeRate)) var currencyConversion: CurrencyConversion? = nil

    let totalBalance: Zatoshi
    let shieldedBalance: Zatoshi
    let transparentBalance: Zatoshi
    let showsBreakdown: Bool
    let canShield: Bool
    let tokenName: String
    let transactions: [TransactionState]
    let showZecAsPrimary: Bool
    let onToggleBalanceDisplay: () -> Void
    let onShieldTapped: () -> Void

    var body: some View {
        WithPerceptionTracking {
            VStack(alignment: .leading, spacing: 0) {
                ZappSectionLabel(text: String(localizable: .zappPayTotalBalance))
                    .padding(.bottom, 8)

                amount

                if totalBalance.amount > 0 {
                    ZappBalanceChart(transactions: transactions, tokenName: tokenName)
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

    private var amount: some View {
        Button(action: onToggleBalanceDisplay) {
            VStack(alignment: .leading, spacing: 2) {
                if let fiat, !showZecAsPrimary, !isSensitiveContentHidden {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(fiat.whole)
                            .zappFont(Constants.hero, style: ZappColors.text)

                        Text(fiat.fraction)
                            .zappFont(Constants.heroFraction, style: ZappColors.textMuted)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(Constants.heroMinimumScale)

                    Text("\(zecText) \(tokenName)")
                        .zappFont(.caption, style: ZappColors.textMuted)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(zecText)
                            .zappFont(Constants.hero, style: ZappColors.text)
                            .lineLimit(1)
                            .minimumScaleFactor(Constants.heroMinimumScale)

                        Text(tokenName)
                            .zappFont(Constants.ticker, style: ZappColors.textMuted)
                    }

                    if let fiat, !isSensitiveContentHidden {
                        Text("\(fiat.whole)\(fiat.fraction)")
                            .zappFont(.caption, style: ZappColors.textMuted)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.zappPress)
        .disabled(fiat == nil)
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
        hidable(totalBalance.decimalString())
    }

    /// nil when no exchange rate has been fetched — the hero then stays ZEC-only and the tap-to-flip
    /// is disabled, rather than showing a fabricated fiat figure.
    private var fiat: (whole: String, fraction: String)? {
        guard let currencyConversion else { return nil }

        let formatted: String = currencyConversion.convert(totalBalance)
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
