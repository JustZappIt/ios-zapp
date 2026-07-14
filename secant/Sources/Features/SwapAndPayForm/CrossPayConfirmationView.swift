//
//  CrossPayConfirmation.swift
//  Zashi
//
//  Created by Lukáš Korba on 09-01-2025.
//

import SwiftUI
import ComposableArchitecture

// FIXME: Candidate for removal from the project
struct CrossPayConfirmationView: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let cardHeight: CGFloat = 94
        static let vendorIconSize: CGFloat = 24
        static let vendorIconBox: CGFloat = 32
        static let tickerSize: CGFloat = 24
        static let tickerBadgeSize: CGFloat = 14
    }

    @Perception.Bindable var store: StoreOf<SwapAndPay>
    let tokenName: String

    init(store: StoreOf<SwapAndPay>, tokenName: String) {
        self.store = store
        self.tokenName = tokenName
    }

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(
                    title: title,
                    containerColor: .bg,
                    titleStyle: .displaySecondary,
                    left: { EmptyView() },
                    right: { EmptyView() }
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: Design.Spacing._2xl) {
                        quoteCards

                        sendTo

                        if store.walletAccounts.count > 1 {
                            sendFrom
                        }

                        VStack(spacing: Design.Spacing._lg) {
                            summaryRow(String(localizable: .sendAmount), "\(store.zecToBeSpendInQuote) \(tokenName)")
                            summaryRow(String(localizable: .sendFeeSummary), "\(store.totalFeesStr) \(tokenName)")

                            Rectangle()
                                .fill(ZappColors.border.color(colorScheme))
                                .frame(height: 1)

                            summaryRow(String(localizable: .crosspayTotal), "\(store.totalZecToBeSpendInQuote) \(tokenName)")

                            HStack {
                                Spacer()

                                Text(store.totalZecUsdToBeSpendInQuote)
                                    .zappFont(.caption, style: ZappColors.textMuted)
                            }
                        }
                    }
                    .padding(.horizontal, Design.Spacing._2xl)
                    .padding(.top, Design.Spacing._2xl)
                    .padding(.bottom, ZappNavBar.pushedFloatingMargin)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .zashiBack(
                primaryAction: { confirmButton },
                customDismiss: { store.send(.backFromConfirmationTapped) }
            )
        }
    }

    private var title: String {
        store.selectedWalletAccount?.vendor == .keystone
            ? String(localizable: .sendReview)
            : String(localizable: .sendConfirmationTitle)
    }

    @ViewBuilder private var confirmButton: some View {
        if store.selectedWalletAccount?.vendor == .keystone {
            ZappButton(title: String(localizable: .keystoneConfirmPay)) {
                store.send(.confirmWithKeystoneTapped)
            }
        } else {
            ZappButton(title: String(localizable: .crosspayPay)) {
                store.send(.confirmButtonTapped)
            }
        }
    }

    private var quoteCards: some View {
        ZStack {
            HStack(spacing: Design.Spacing._md) {
                quoteCard(
                    ticker: AnyView(zecTickerLogo(colorScheme).scaleEffect(0.8)),
                    amount: store.zecToBeSpendInQuote,
                    usd: store.zecUsdToBeSpendInQuote
                )

                quoteCard(
                    ticker: AnyView(tokenTicker(asset: store.selectedAsset, colorScheme).scaleEffect(0.8)),
                    amount: store.tokenToBeReceivedInQuote,
                    usd: store.tokenUsdToBeReceivedInQuote
                )
            }

            FloatingArrow()
        }
    }

    private func quoteCard(ticker: AnyView, amount: String, usd: String) -> some View {
        VStack(spacing: Design.Spacing._xs) {
            ticker

            Text(amount)
                .zappFont(.sectionTitle, style: ZappColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.1)

            Text(usd)
                .zappFont(.caption, style: ZappColors.textMuted)
        }
        .padding(.horizontal, Design.Spacing._2xl)
        .padding(.vertical, Design.Spacing._lg)
        .frame(maxWidth: .infinity)
        .frame(height: Constants.cardHeight)
        .background(ZappColors.surfaceAlt.color(colorScheme))
    }

    private var sendTo: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappSectionLabel(text: String(localizable: .sendToSummary))

            if let alias = store.selectedContact?.name {
                Text(alias)
                    .zappFont(.rowTitle, style: ZappColors.text)
            }

            Text(store.address)
                .zappFont(.mono, style: ZappColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sendFrom: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappSectionLabel(text: String(localizable: .accountsSendingFrom))

            if let selectedWalletAccount = store.selectedWalletAccount {
                HStack(spacing: Design.Spacing._lg) {
                    selectedWalletAccount.vendor.icon()
                        .resizable()
                        .frame(width: Constants.vendorIconSize, height: Constants.vendorIconSize)
                        .frame(width: Constants.vendorIconBox, height: Constants.vendorIconBox)
                        .background(ZappColors.surfaceAlt.color(colorScheme))

                    Text(selectedWalletAccount.vendor.name())
                        .zappFont(.rowTitle, style: ZappColors.text)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .zappFont(.body, style: ZappColors.textMuted)

            Spacer()

            Text(value)
                .zappFont(.rowTitle, style: ZappColors.text)
        }
    }

    @ViewBuilder func zecTickerLogo(_ colorScheme: ColorScheme) -> some View {
        Asset.Assets.Brandmarks.brandmarkMax.image
            .zImage(width: Constants.tickerSize, height: Constants.tickerSize, style: ZappColors.text)
            .overlay(alignment: .bottomTrailing) {
                Asset.Assets.Icons.shieldTickFilled.image
                    .zImage(width: 11, height: 11, style: ZappColors.text)
                    .frame(width: Constants.tickerBadgeSize, height: Constants.tickerBadgeSize)
                    .background(ZappColors.surfaceAlt.color(colorScheme))
                    .offset(x: 4, y: 4)
            }
    }
}

#Preview {
    NavigationView {
        CrossPayConfirmationView(store: SwapAndPay.initial, tokenName: "ZEC")
    }
}
