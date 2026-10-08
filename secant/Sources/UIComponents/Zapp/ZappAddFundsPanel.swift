//
//  ZappAddFundsPanel.swift
//  Zapp
//
//  Android's `AddFundsPanel`: the empty-wallet explanation a money flow shows in place of its
//  form. Display only: the screen puts Add ZEC in its bottom bar, beside back, where every Zapp
//  screen keeps its primary action.
//

import SwiftUI

struct ZappAddFundsPanel: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let iconBoxSize: CGFloat = 88
        static let iconSize: CGFloat = 44
    }

    let message: String

    var body: some View {
        VStack(spacing: 0) {
            Asset.Assets.Icons.walletBuy.image
                .zImage(size: Constants.iconSize, style: ZappColors.textSubtle)
                .frame(width: Constants.iconBoxSize, height: Constants.iconBoxSize)
                .background(ZappColors.surfaceAlt.color(colorScheme))
                .accessibilityHidden(true)
                .padding(.bottom, Design.Spacing._3xl)

            Text(localizable: .topUpAddFundsPanelTitle)
                .zappFont(.sectionTitle, style: ZappColors.text)
                .multilineTextAlignment(.center)
                .padding(.bottom, Design.Spacing._md)

            Text(message)
                .zappFont(.body, style: ZappColors.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
