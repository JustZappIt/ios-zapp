//
//  ZappWalletAccountsSheet.swift
//  Zapp
//
//  The Pay header's wallet switcher: every account the app holds, and the door to connecting a
//  Keystone. Reads the same `StoreOf<Home>` and sends the same actions as upstream's
//  `WalletAccountsSheet`, which stays byte-for-byte on the dead `HomeView`.
//

import ComposableArchitecture
import SwiftUI

struct ZappWalletAccountsSheet: View {
    enum Accessibility {
        static let connectButton = "walletAccounts.connectButton"
        static let promo = "walletAccounts.keystonePromo"
    }

    private enum Constants {
        static let contentPadding: CGFloat = 24
        static let topPadding: CGFloat = 16
        static let rowHeight: CGFloat = 56
        static let promoImageHeight: CGFloat = 148
        static let promoTextLines: CGFloat = 2
        static let checkSize: CGFloat = 18
        static let buttonHeight: CGFloat = 52
    }

    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<Home>

    /// Derived from this sheet's own layout so the detent keeps matching the content: the heading,
    /// one row per account, and — until a Keystone is connected — the promo panel and the button.
    /// `.large` is offered alongside it so larger type is never trapped.
    static func detentHeight(accountCount: Int, showsKeystoneDoor: Bool) -> CGFloat {
        let heading = Constants.topPadding
            + ZappTextStyle.sectionTitle.lineHeight
            + Design.Spacing._xl
        let rows = Constants.rowHeight * CGFloat(max(accountCount, 1))
        let door = showsKeystoneDoor
            ? Design.Spacing._xl
                + Design.Spacing._xl * 2
                + ZappTextStyle.rowTitle.lineHeight
                + Design.Spacing._xxs
                + ZappTextStyle.caption.lineHeight * Constants.promoTextLines
                + Constants.promoImageHeight
                + Design.Spacing._xl
                + Constants.buttonHeight
            : 0

        return heading + rows + door + Design.Spacing.sheetBottomSpace
    }

    var body: some View {
        WithPerceptionTracking {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(localizable: .keystoneDrawerTitle)
                        .zappFont(.sectionTitle, style: ZappColors.text)
                        .padding(.top, Constants.topPadding)
                        .padding(.bottom, Design.Spacing._xl)

                    accounts

                    if !store.isKeystoneConnected {
                        promo
                            .padding(.top, Design.Spacing._xl)

                        ZappButton(title: String(localizable: .keystoneConnect)) {
                            store.send(.addKeystoneHWWalletTapped)
                        }
                        .accessibilityIdentifier(Accessibility.connectButton)
                        .padding(.top, Design.Spacing._xl)
                    }
                }
                .padding(.horizontal, Constants.contentPadding)
                .padding(.bottom, Design.Spacing.sheetBottomSpace)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(ZappColors.surface.color(colorScheme))
        }
    }

    private var accounts: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.walletAccounts.enumerated()), id: \.element) { index, account in
                if index > 0 {
                    ZappRowDivider(inset: true)
                }

                ZappRow(
                    title: account.vendor.name(),
                    subtitle: account.unifiedAddress?.zip316 ?? String(localizable: .receiveErrorCantExtractUnifiedAddress),
                    logo: account.vendor.icon(),
                    trailing: {
                        if store.selectedWalletAccount == account {
                            Asset.Assets.check.image
                                .zImage(width: Constants.checkSize, height: Constants.checkSize, style: ZappColors.accent)
                        }
                    }
                ) {
                    store.send(.walletAccountTapped(account))
                }
                .accessibilityAddTraits(store.selectedWalletAccount == account ? .isSelected : [])
            }
        }
        .overlay(
            Rectangle()
                .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
        )
    }

    private var promo: some View {
        Button {
            store.send(.keystoneBannerTapped)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: Design.Spacing._xxs) {
                    Text(localizable: .keystoneDrawerBannerTitle)
                        .zappFont(.rowTitle, style: ZappColors.text)

                    Text(localizable: .keystoneDrawerBannerDesc)
                        .zappFont(.caption, style: ZappColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Design.Spacing._xl)

                Asset.Assets.Partners.keystonePromo.image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: Constants.promoImageHeight)
                    .clipped()
                    .accessibilityHidden(true)
            }
            .background(ZappColors.surfaceAlt.color(colorScheme))
            .overlay(
                Rectangle()
                    .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.zappPress)
        .accessibilityIdentifier(Accessibility.promo)
    }
}

#Preview {
    ZappWalletAccountsSheet(store: Home.placeholder)
        .applyScreenBackground()
}
