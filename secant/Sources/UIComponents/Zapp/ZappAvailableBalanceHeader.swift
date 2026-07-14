//
//  ZappAvailableBalanceHeader.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI
@preconcurrency import ZcashLightClientKit

/// Fiat-first available balance shared by Send and Swap, matching Android's
/// `SendBalanceHeader`. The caller supplies the conversion so this component
/// remains presentation-only and does not own wallet or exchange-rate state.
struct ZappAvailableBalanceHeader: View {
    @Shared(.appStorage(.sensitiveContent)) private var isSensitiveContentHidden = false

    let balance: Zatoshi
    let fiatText: String?
    let tokenName: String

    @State private var isFiatPrimary = true

    var body: some View {
        VStack(spacing: 4) {
            Text(localizable: .zappWalletAvailableBalance)
                .zappFont(.caption, style: ZappColors.textMuted)

            Button {
                guard fiatText != nil else { return }
                isFiatPrimary.toggle()
            } label: {
                VStack(spacing: 2) {
                    Text(primaryText)
                        .zappFont(.balanceDisplay, style: ZappColors.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)

                    if let secondaryText {
                        Text(secondaryText)
                            .zappFont(.body, style: ZappColors.textMuted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.zappPress)
            .disabled(fiatText == nil)
            .accessibilityLabel(String(localizable: .zappWalletToggleBalanceCurrency))
        }
        .frame(maxWidth: .infinity)
    }

    private var primaryText: String {
        if isSensitiveContentHidden {
            return String(localizable: .generalHideBalancesMost)
        }
        if isFiatPrimary, let fiatText {
            return fiatText
        }
        return zecText
    }

    private var secondaryText: String? {
        guard !isSensitiveContentHidden, let fiatText else { return nil }
        return isFiatPrimary ? zecText : fiatText
    }

    private var zecText: String {
        "\(balance.decimalString()) \(tokenName)"
    }
}
