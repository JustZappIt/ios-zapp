//
//  PoolBalancesSheet.swift
//  Zapp
//
//  Live Zapp presentation of the wallet's Sapling, Orchard, Ironwood, and transparent pools.
//

import ComposableArchitecture
import SwiftUI
@preconcurrency import ZcashLightClientKit

struct PoolBalancesSheet: View {
    enum Accessibility {
        static let dismissButton = "poolBalances.dismissButton"
        static let ironwood = "poolBalances.ironwood"
        static let openButton = "poolBalances.openButton"
        static let orchard = "poolBalances.orchard"
        static let sapling = "poolBalances.sapling"
        static let total = "poolBalances.total"
        static let transparent = "poolBalances.transparent"
    }

    private enum Constants {
        static let cardSpacing: CGFloat = 8
        static let contentPadding: CGFloat = 20
        static let cardHorizontalPadding: CGFloat = 16
        static let cardVerticalPadding: CGFloat = 12
    }

    @Environment(\.colorScheme) private var colorScheme
    @Dependency(\.date) private var date
    @Dependency(\.userStoredPreferences) private var userStoredPreferences
    @Shared(.inMemory(.exchangeRate)) private var currencyConversion: CurrencyConversion? = nil
    @Shared(.appStorage(.sensitiveContent)) private var isSensitiveContentHidden = false
    @Shared(.inMemory(.zappFiatQuote)) private var zappFiatQuote: ZappFiatQuote? = nil

    @Perception.Bindable var store: StoreOf<WalletBalances>
    let tokenName: String
    let onDismiss: () -> Void

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(localizable: .poolBalancesTitle)
                            .zappFont(.screenTitle, style: ZappColors.text)
                            .padding(.top, Design.Spacing._xl)

                        Text(localizable: .poolBalancesDesc)
                            .zappFont(.body, style: ZappColors.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                            .padding(.top, Design.Spacing._sm)
                            .padding(.bottom, Design.Spacing._3xl)

                        poolCard(
                            title: String(localizable: .poolBalancesTotalBalance),
                            balance: store.totalBalance,
                            identifier: Accessibility.total,
                            dimmedToken: true
                        )
                        .padding(.bottom, Constants.cardSpacing)

                        HStack(spacing: Constants.cardSpacing) {
                            poolCard(
                                title: String(localizable: .poolBalancesIronwood),
                                balance: store.ironwoodPoolBalance,
                                identifier: Accessibility.ironwood
                            )
                            poolCard(
                                title: String(localizable: .poolBalancesOrchard),
                                balance: store.orchardPoolBalance,
                                identifier: Accessibility.orchard
                            )
                        }
                        .padding(.bottom, Constants.cardSpacing)

                        HStack(spacing: Constants.cardSpacing) {
                            poolCard(
                                title: String(localizable: .poolBalancesSapling),
                                balance: store.saplingPoolBalance,
                                identifier: Accessibility.sapling
                            )
                            poolCard(
                                title: String(localizable: .poolBalancesTransparent),
                                balance: store.transparentPoolBalance,
                                identifier: Accessibility.transparent
                            )
                        }
                    }
                }

                ZappButton(title: String(localizable: .poolBalancesGotIt), action: onDismiss)
                    .accessibilityIdentifier(Accessibility.dismissButton)
                    .padding(.top, Design.Spacing._2xl)
                    .padding(.bottom, Design.Spacing.sheetBottomSpace)
            }
            .padding(.horizontal, Constants.contentPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(ZappColors.surface.color(colorScheme))
        }
    }

    @ViewBuilder
    private func poolCard(
        title: String,
        balance: Zatoshi,
        identifier: String,
        dimmedToken: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .zappFont(.caption, style: ZappColors.textMuted)
                .padding(.bottom, Design.Spacing._sm)

            HStack(spacing: Design.Spacing._sm) {
                // Expanded representation keeps all eight fractional digits available instead
                // of rounding away zatoshi. `couldBeHidden` masks every card when privacy mode is on.
                ZatoshiRepresentationView(
                    balance: balance,
                    fontName: FontFamily.Inter.semiBold.name,
                    mostSignificantFontSize: 16,
                    leastSignificantFontSize: 12,
                    format: .expanded,
                    couldBeHidden: true
                )
                .foregroundStyle(ZappColors.text.color(colorScheme))

                if !isSensitiveContentHidden {
                    Text(tokenName)
                        .zappFont(.rowTitle, style: dimmedToken ? ZappColors.textMuted : ZappColors.text)
                }
            }

            if let fiatConversion {
                Text(fiatConversion.convert(balance))
                    .hiddenIfSet()
                    .zappFont(.caption, style: ZappColors.textSubtle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Constants.cardHorizontalPadding)
        .padding(.vertical, Constants.cardVerticalPadding)
        .background(ZappColors.surfaceAlt.color(colorScheme))
        .overlay {
            Rectangle()
                .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(
            Self.accessibilityValue(
                balance: balance,
                tokenName: tokenName,
                isSensitiveContentHidden: isSensitiveContentHidden
            )
        )
        .accessibilityIdentifier(identifier)
    }

    static func accessibilityValue(
        balance: Zatoshi,
        tokenName: String,
        isSensitiveContentHidden: Bool
    ) -> String {
        guard !isSensitiveContentHidden else {
            return String(localizable: .generalHideBalancesMost)
        }
        return "\(balance.atLeastThreeDecimalsZashiFormatted()) \(tokenName)"
    }

    private var fiatConversion: CurrencyConversion? {
        ZappFiatRate.resolve(
            preference: userStoredPreferences.exchangeRate(),
            conversion: currencyConversion,
            fallback: zappFiatQuote,
            at: date.now()
        )
    }
}
