//
//  ZappTopUpSheet.swift
//  Zapp
//
//  Android's `TopUpView.kt`: "How are you topping up?" — pick where the ZEC comes from, then show
//  the address that source can actually send to.
//

import SwiftUI

struct ZappTopUpSheet: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let iconBoxSize: CGFloat = 36
        static let iconSize: CGFloat = 20
        static let title = ZappTextStyle(weight: .black, size: 18, lineHeight: 24, tracking: -0.3)
    }

    let onSourcePicked: (SendCoordFlow.TopUpSource) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(localizable: .topUpTitle)
                .zappFont(Constants.title, style: ZappColors.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Design.Spacing._xs)

            Text(localizable: .topUpSubtitle)
                .zappFont(.body, style: ZappColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Design.Spacing._xl)

            sourceRow(
                icon: Asset.Assets.Icons.coinsSwap.image,
                title: String(localizable: .topUpFromExchangeTitle),
                subtitle: String(localizable: .topUpFromExchangeSubtitle),
                source: .exchange
            )
            .padding(.bottom, Design.Spacing._md)

            sourceRow(
                icon: Asset.Assets.Icons.connectWallet.image,
                title: String(localizable: .topUpFromWalletTitle),
                subtitle: String(localizable: .topUpFromWalletSubtitle),
                source: .wallet
            )
        }
        // Sized to its content by `zashiSheet`, so the sheet ends just below the last row.
        .padding(.horizontal, Design.Spacing._3xl)
        .padding(.top, Design.Spacing._3xl)
        .padding(.bottom, Design.Spacing._lg)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(ZappColors.surface.color(colorScheme))
    }

    private func sourceRow(
        icon: Image,
        title: String,
        subtitle: String,
        source: SendCoordFlow.TopUpSource
    ) -> some View {
        Button {
            onSourcePicked(source)
        } label: {
            HStack(spacing: Design.Spacing._xl) {
                icon
                    .zImage(size: Constants.iconSize, style: ZappColors.accentText)
                    .frame(width: Constants.iconBoxSize, height: Constants.iconBoxSize)
                    .background(ZappColors.accentSoft.color(colorScheme))

                VStack(alignment: .leading, spacing: Design.Spacing._xxs) {
                    Text(title)
                        .zappFont(.rowTitle, style: ZappColors.text)

                    Text(subtitle)
                        .zappFont(.rowSubtitle, style: ZappColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Design.Spacing._xl)
            .overlay(Rectangle().strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.zappPress)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    ZappTopUpSheet { _ in }
}
