//
//  RequestPaymentConfirmationView.swift
//  Zashi
//
//  Created by Lukáš Korba on 28.11.2023.
//

import SwiftUI
import ComposableArchitecture
@preconcurrency import ZcashLightClientKit

struct RequestPaymentConfirmationView: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let vendorIconSize: CGFloat = 24
        static let vendorIconBox: CGFloat = 32
        static let inlineIconSize: CGFloat = 18
    }

    @Perception.Bindable var store: StoreOf<SendConfirmation>
    let tokenName: String

    init(store: StoreOf<SendConfirmation>, tokenName: String) {
        self.store = store
        self.tokenName = tokenName
    }

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(
                    title: String(localizable: .sendRequestPaymentTitle),
                    containerColor: .bg,
                    titleStyle: .displaySecondary,
                    left: { EmptyView() },
                    right: { EmptyView() }
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: Design.Spacing._2xl) {
                        requestedAmount
                        requestedBy

                        if !store.isTransparentAddress || store.alias == nil {
                            addressActions
                        }

                        if store.walletAccounts.count > 1 {
                            sendingFrom
                        }

                        if !store.message.isEmpty {
                            memo
                        }

                        feeRow
                        totalRow
                    }
                    .padding(.horizontal, Design.Spacing._2xl)
                    .padding(.top, Design.Spacing._2xl)
                    .padding(.bottom, ZappNavBar.pushedFloatingMargin)
                }
                .alert($store.scope(state: \.alert, action: \.alert))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .orchardSpendWarningSheet(
                isPresented: $store.isOrchardWarningPresented,
                onContinue: { store.send(.orchardWarningContinueTapped) },
                onCancel: { store.send(.orchardWarningCancelTapped) },
                onDismiss: { store.send(.orchardWarningDismissed) }
            )
            .onAppear {
                store.send(.onAppear)
                store.send(.confirmationScreenAppeared)
            }
            .zashiBack(
                store.isSending,
                primaryAction: { confirmButton },
                customDismiss: { store.send(.goBackTappedFromRequestZec) }
            )
        }
        .navigationBarBackButtonHidden()
    }

    @ViewBuilder private var confirmButton: some View {
        if let vendor = store.selectedWalletAccount?.vendor, vendor == .keystone {
            ZappButton(title: String(localizable: .keystoneConfirm)) {
                store.send(.confirmWithKeystoneTapped)
            }
        } else if store.isSending {
            ZappButton(title: String(localizable: .sendSending), isEnabled: false) { }
        } else {
            ZappButton(title: String(localizable: .generalSend)) {
                store.send(.sendTapped)
            }
        }
    }

    private var requestedAmount: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            BalanceWithIconView(balance: store.amount)

            Text(store.currencyAmount.data)
                .zappFont(.rowTitle, style: ZappColors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var requestedBy: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappSectionLabel(text: String(localizable: .sendRequestPaymentRequestedBy))

            if let alias = store.alias {
                Text(alias)
                    .zappFont(.rowTitle, style: ZappColors.text)
            }

            Text(store.addressToShow)
                .zappFont(.mono, style: ZappColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var addressActions: some View {
        HStack(spacing: Design.Spacing._md) {
            if !store.isTransparentAddress {
                inlineButton(
                    title: store.isAddressExpanded
                        ? String(localizable: .generalHide)
                        : String(localizable: .generalShow),
                    icon: Asset.Assets.chevronDown.image,
                    rotated: store.isAddressExpanded
                ) {
                    store.send(.showHideButtonTapped)
                }
            }

            if store.alias == nil {
                inlineButton(
                    title: String(localizable: .generalSave),
                    icon: Asset.Assets.Icons.userPlus.image,
                    rotated: false
                ) {
                    store.send(.saveAddressTapped(store.address.redacted))
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func inlineButton(
        title: String,
        icon: Image,
        rotated: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Design.Spacing._sm) {
                icon
                    .zImage(width: Constants.inlineIconSize, height: Constants.inlineIconSize, style: ZappColors.text)
                    .rotationEffect(.degrees(rotated ? 180 : 0))

                Text(title)
                    .zappFont(.buttonSmall, style: ZappColors.text)
            }
            .padding(.horizontal, Design.Spacing._lg)
            .padding(.vertical, Design.Spacing._md)
            .background(ZappColors.surfaceAlt.color(colorScheme))
        }
        .buttonStyle(.zappPress)
    }

    private var sendingFrom: some View {
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

    private var memo: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappSectionLabel(text: String(localizable: .sendRequestPaymentFor))

            Text(store.message)
                .zappFont(.body, style: ZappColors.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Design.Spacing._lg)
                .background(ZappColors.surfaceInput.color(colorScheme))
        }
    }

    private var feeRow: some View {
        HStack {
            Text(localizable: .sendFeeSummary)
                .zappFont(.body, style: ZappColors.textMuted)

            Spacer()

            ZatoshiRepresentationView(
                balance: store.feeRequired,
                fontName: FontFamily.Inter.semiBold.name,
                mostSignificantFontSize: 14,
                leastSignificantFontSize: 7,
                format: .expanded
            )
        }
    }

    private var totalRow: some View {
        HStack {
            Text(localizable: .sendRequestPaymentTotal)
                .zappFont(.body, style: ZappColors.textMuted)

            Spacer()

            ZatoshiRepresentationView(
                balance: store.amount + store.feeRequired,
                fontName: FontFamily.Inter.semiBold.name,
                mostSignificantFontSize: 14,
                leastSignificantFontSize: 7,
                format: .expanded
            )
        }
    }
}

#Preview {
    NavigationView {
        RequestPaymentConfirmationView(
            store: SendConfirmation.initial,
            tokenName: "ZEC"
        )
    }
}
