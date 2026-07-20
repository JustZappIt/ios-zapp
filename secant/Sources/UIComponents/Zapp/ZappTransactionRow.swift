//
//  ZappTransactionRow.swift
//  Zapp
//
//  A fork-owned transaction row, so upstream's `TransactionRowView` stays pristine.
//
//  Not a reskin in place: upstream's row has a fixed signature and we need an extra
//  `showZecAsPrimary` (the balance card and every row flip together, as on Android).
//  Changing an upstream component's signature is a merge tax every month; a parallel
//  fork-owned row costs nothing, and upstream's keeps merging clean.
//

import ComposableArchitecture
import SwiftUI

struct ZappTransactionRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Dependency(\.date) private var date
    @Dependency(\.userStoredPreferences) private var userStoredPreferences

    private enum Constants {
        static let iconBox: CGFloat = 40
        static let iconSize: CGFloat = 20
        static let unreadDot: CGFloat = 8
        static let horizontalPadding: CGFloat = 18
        static let verticalPadding: CGFloat = 12
        static let spacing: CGFloat = 12
    }

    @Shared(.appStorage(.sensitiveContent)) var isSensitiveContentHidden = false
    @Shared(.inMemory(.exchangeRate)) var currencyConversion: CurrencyConversion? = nil
    @Shared(.inMemory(.zappFiatQuote)) var zappFiatQuote: ZappFiatQuote? = nil

    let transaction: TransactionState
    var tokenName = "ZEC"
    var isUnread = false
    var isSwap = false
    var showZecAsPrimary = true
    var divider = true
    let action: () -> Void

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Button(action: action) {
                    HStack(spacing: Constants.spacing) {
                        icon

                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .zappFont(.rowTitle, style: ZappColors.text)
                                .lineLimit(1)

                            Text(transaction.dateString ?? "")
                                .zappFont(.rowSubtitle, style: ZappColors.textMuted)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        amounts
                    }
                    .padding(.horizontal, Constants.horizontalPadding)
                    .padding(.vertical, Constants.verticalPadding)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if divider {
                    ZappRowDivider(inset: true)
                }
            }
        }
    }

    private var icon: some View {
        ZStack(alignment: .topTrailing) {
            transaction.transationIcon
                .resizable()
                .scaledToFit()
                .frame(width: Constants.iconSize, height: Constants.iconSize)
                .foregroundStyle(ZappColors.text.color(colorScheme))
                .frame(width: Constants.iconBox, height: Constants.iconBox)
                .background(ZappColors.surfaceAlt.color(colorScheme))

            // Kept from upstream and deliberately NOT dropped: Android's row has no
            // unread affordance, but iOS has no other one either.
            if isUnread {
                Rectangle()
                    .fill(ZappColors.accent.color(colorScheme))
                    .frame(width: Constants.unreadDot, height: Constants.unreadDot)
                    .offset(x: 2, y: -2)
            }
        }
    }

    private var title: String {
        transaction.isPending
            ? String(localizable: .transactionHistoryThreeDots(transaction.title()))
            : transaction.title()
    }

    private var amounts: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(primaryAmount)
                .zappFont(.rowTitle, color: transaction.titleColor(colorScheme))
                .lineLimit(1)

            if let secondary = secondaryAmount {
                Text(secondary)
                    .zappFont(.caption, style: ZappColors.textMuted)
                    .lineLimit(1)
            }
        }
    }

    private var zecText: String {
        isSensitiveContentHidden
            ? String(localizable: .generalHideBalancesMost)
            : "\(transaction.isSpending ? "-" : "+")\(transaction.zecAmount.decimalString()) \(tokenName)"
    }

    private var fiatText: String? {
        guard let conversion = ZappFiatRate.resolve(
            preference: userStoredPreferences.exchangeRate(),
            conversion: currencyConversion,
            fallback: zappFiatQuote,
            at: date.now()
        ) else {
            return nil
        }
        guard !isSensitiveContentHidden else { return String(localizable: .generalHideBalancesMost) }

        let converted: String = conversion.convert(transaction.zecAmount)

        return "\(transaction.isSpending ? "-" : "+")\(converted)"
    }

    private var primaryAmount: String {
        showZecAsPrimary ? zecText : (fiatText ?? zecText)
    }

    private var secondaryAmount: String? {
        guard let fiatText else { return nil }

        return showZecAsPrimary ? fiatText : zecText
    }
}
