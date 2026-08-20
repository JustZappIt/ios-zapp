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
        /// Android's sheet gutter (`BalanceBreakdownView.kt`: start/end = 24.dp).
        static let contentPadding: CGFloat = 24
        /// `ZappBorderedCard(padding = 16.dp)` — uniform, unlike the split padding it replaces.
        static let cardPadding: CGFloat = 16
        static let topPadding: CGFloat = 16
        static let amountSize: CGFloat = 15
        static let amountFractionSize: CGFloat = 12
        static let amountLineHeight: CGFloat = 20
        static let cardRows: CGFloat = 3
        /// The description wraps to three lines at the narrowest width the app supports.
        static let subtitleLines: CGFloat = 3
        static let buttonHeight: CGFloat = 52
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

    /// Derived from this sheet's own layout rather than eyeballed, so the detent keeps matching the
    /// content if a padding changes: heading block, three card rows, the gap before the button, and
    /// the button itself. The `ScrollView` absorbs whatever larger type adds, and `.large` is
    /// offered alongside it so the content can never be trapped.
    static var detentHeight: CGFloat {
        let cardHeight = Constants.cardPadding * 2
            + ZappTextStyle.rowSubtitle.lineHeight
            + Design.Spacing._sm
            + Constants.amountLineHeight
            + ZappTextStyle.caption.lineHeight
        let heading = Constants.topPadding
            + ZappTextStyle.sheetTitle.lineHeight
            + Design.Spacing._md
            + ZappTextStyle.body.lineHeight * Constants.subtitleLines
            + Design.Spacing._3xl

        return heading
            + cardHeight * Constants.cardRows
            + Constants.cardSpacing * (Constants.cardRows - 1)
            + Design.Spacing._4xl
            + Constants.buttonHeight
            + Design.Spacing.sheetBottomSpace
    }

    var body: some View {
        WithPerceptionTracking {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(localizable: .poolBalancesTitle)
                        .zappFont(.sheetTitle, style: ZappColors.text)
                        .padding(.top, Constants.topPadding)

                    Text(localizable: .poolBalancesDesc)
                        .zappFont(.body, style: ZappColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .padding(.top, Design.Spacing._md)
                        .padding(.bottom, Design.Spacing._3xl)

                    poolCard(
                        title: String(localizable: .poolBalancesTotalBalance),
                        balance: store.totalBalance,
                        identifier: Accessibility.total,
                        isTotal: true
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

                    // Android scrolls the button with the content instead of pinning it, so a sheet
                    // taller than its content never strands it against the bottom edge.
                    ZappButton(title: String(localizable: .poolBalancesGotIt), action: onDismiss)
                        .accessibilityIdentifier(Accessibility.dismissButton)
                        .padding(.top, Design.Spacing._4xl)
                }
                .padding(.horizontal, Constants.contentPadding)
                .padding(.bottom, Design.Spacing.sheetBottomSpace)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(ZappColors.surface.color(colorScheme))
        }
    }

    @ViewBuilder
    private func poolCard(
        title: String,
        balance: Zatoshi,
        identifier: String,
        isTotal: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .zappFont(.rowSubtitle, style: ZappColors.textMuted)
                .padding(.bottom, Design.Spacing._sm)

            HStack(spacing: Design.Spacing._sm) {
                // Expanded representation keeps all eight fractional digits available instead
                // of rounding away zatoshi. `couldBeHidden` masks every card when privacy mode is on.
                ZatoshiRepresentationView(
                    balance: balance,
                    fontName: FontFamily.Inter.black.name,
                    mostSignificantFontSize: Constants.amountSize,
                    leastSignificantFontSize: Constants.amountFractionSize,
                    format: .expanded,
                    couldBeHidden: true
                )
                .foregroundStyle(ZappColors.text.color(colorScheme))

                if !isSensitiveContentHidden {
                    Text(tokenName)
                        .zappFont(.rowTitle, style: ZappColors.text)
                }
            }

            if let fiatConversion {
                Text(fiatConversion.convert(balance))
                    .hiddenIfSet()
                    .zappFont(.caption, style: ZappColors.textSubtle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Constants.cardPadding)
        // Android's card sits on the same `surface` as the sheet; only the border separates it,
        // and the total card takes a `text` border so it reads as the sum of the four below it.
        .background(ZappColors.surface.color(colorScheme))
        .overlay {
            Rectangle()
                .strokeBorder((isTotal ? ZappColors.text : ZappColors.border).color(colorScheme), lineWidth: 1)
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

private extension ZappTextStyle {
    /// Android renders this heading as `sectionTitle` at Black weight (`BalanceBreakdownView.kt`).
    static let sheetTitle = ZappTextStyle(weight: .black, size: 18, lineHeight: 24, tracking: -0.3)
}
