//
//  ZappWalletAccountsSheet.swift
//  Zapp
//
//  Android's `AccountListView` ("Wallets & Hardware"), opened from the You tab's Hardware wallet
//  row. The legacy `WalletAccountsSheet` lives on the unreachable `HomeView`; this is the same
//  content in the Zapp shell, sending the same Home actions, so Root's existing account-switch and
//  Add Keystone handling serve both.
//

import ComposableArchitecture
import SwiftUI

struct ZappWalletAccountsSheet: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let contentPadding: CGFloat = 24
        static let rowInset: CGFloat = 4
        static let rowPadding: CGFloat = 16
        static let iconSize: CGFloat = 24
        static let iconPadding: CGFloat = 8
        static let rowSpacing: CGFloat = 8
    }

    @Perception.Bindable var store: StoreOf<Home>

    var body: some View {
        WithPerceptionTracking {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(localizable: .keystoneDrawerTitle)
                        .zappFont(.sectionTitle, style: ZappColors.text)
                        .padding(.horizontal, Constants.contentPadding)
                        .padding(.top, Constants.contentPadding)
                        .padding(.bottom, Constants.contentPadding)

                    VStack(spacing: Constants.rowSpacing) {
                        ForEach(store.walletAccounts, id: \.self) { account in
                            accountRow(account)
                        }
                    }
                    .padding(.horizontal, Constants.rowInset)

                    if store.walletAccounts.isEmpty {
                        ProgressView()
                            .tint(ZappColors.accent.color(colorScheme))
                            .frame(maxWidth: .infinity)
                            .padding(.top, Constants.contentPadding)
                    }

                    // Offered only until a Keystone is connected, as on Android. Unlike Android and the
                    // legacy sheet, Zapp shows no Keystone shop promo here.
                    if !store.isKeystoneConnected {
                        ZappButton(title: String(localizable: .keystoneConnect), variant: .secondary) {
                            store.send(.addKeystoneHWWalletTapped)
                        }
                        .padding(.horizontal, Constants.contentPadding)
                        .padding(.top, Design.Spacing._4xl)
                    }
                }
                .padding(.bottom, Design.Spacing.sheetBottomSpace)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(ZappColors.surface.color(colorScheme))
        }
    }

    private func accountRow(_ account: WalletAccount) -> some View {
        // By id: the selected copy and the listed copy can differ in rotating fields (`privateUA`),
        // which made whole-value equality leave the current account unmarked.
        let isSelected = store.selectedWalletAccount?.id == account.id

        return Button {
            store.send(.walletAccountTapped(account))
        } label: {
            HStack(spacing: Design.Spacing._lg) {
                account.vendor.icon()
                    .resizable()
                    .frame(width: Constants.iconSize, height: Constants.iconSize)
                    .padding(Constants.iconPadding)
                    .background(Circle().fill(ZappColors.surfaceAlt.color(colorScheme)))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Design.Spacing._xs) {
                    Text(account.vendor.name())
                        .zappFont(.rowTitle, style: ZappColors.text)

                    Text((account.unifiedAddress ?? String(localizable: .receiveErrorCantExtractUnifiedAddress)).zip316)
                        .zappFont(.mono, style: ZappColors.textMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Constants.rowPadding)
            .background(isSelected ? ZappColors.surfaceAlt.color(colorScheme) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.zappPress)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
