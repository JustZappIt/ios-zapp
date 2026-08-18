//
//  SendConfirmationView.swift
//
//
//  Created by Lukáš Korba on 28.11.2023.
//

import SwiftUI
import ComposableArchitecture
@preconcurrency import ZcashLightClientKit

struct SendConfirmationView: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let vendorIconSize: CGFloat = 24
        static let vendorIconBox: CGFloat = 32
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
                    title: title,
                    containerColor: .bg,
                    titleStyle: .displaySecondary,
                    left: { EmptyView() },
                    right: { EmptyView() }
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: Design.Spacing._2xl) {
                        total
                        sendingTo

                        if store.walletAccounts.count > 1 {
                            sendingFrom
                        }

                        amountRow
                        feeRow

                        if !store.message.isEmpty {
                            memo
                        }
                    }
                    .padding(.horizontal, Design.Spacing._2xl)
                    .padding(.top, Design.Spacing._2xl)
                    .padding(.bottom, ZappNavBar.pushedFloatingMargin)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .onAppear { store.send(.onAppear) }
            .alert($store.scope(state: \.alert, action: \.alert))
            // A12: shown BEFORE authentication when this account has a live migration run with
            // unmigrated Orchard left — see `MigrationManualSendRisk`.
            .zashiSheet(isPresented: $store.isOrchardWarningPresented) {
                SendOrchardWarningSheet(
                    sendAnywayTapped: { store.send(.orchardWarningSendAnywayTapped) },
                    cancelTapped: { store.send(.orchardWarningCancelTapped) }
                )
            }
            .zashiBack(
                store.isSending,
                primaryAction: { confirmButton },
                customDismiss: { store.send(.cancelTapped) }
            )
        }
        .navigationBarBackButtonHidden()
    }

    private var title: String {
        store.selectedWalletAccount?.vendor == .keystone
            ? String(localizable: .sendReview)
            : String(localizable: .sendConfirmationTitle)
    }

    @ViewBuilder private var confirmButton: some View {
        if store.selectedWalletAccount?.vendor == .keystone {
            ZappButton(title: String(localizable: .keystoneConfirm)) {
                store.send(.confirmWithKeystoneTapped)
            }
        } else if store.isSending {
            ZappButton(title: String(localizable: .sendSending), isEnabled: false) { }
        } else {
            ZappButton(title: String(localizable: .generalSend)) {
                store.send(.sendTapped)
            }
            .accessibilityIdentifier(AccessibilityID.SendConfirmation.sendButton)
        }
    }

    private var total: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappSectionLabel(text: String(localizable: .sendAmountSummary))

            BalanceWithIconView(balance: store.amount + store.feeRequired)

            Text(store.currencyAmount.data)
                .zappFont(.rowTitle, style: ZappColors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sendingTo: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappSectionLabel(text: String(localizable: .sendToSummary))

            if let alias = store.alias {
                Text(alias)
                    .zappFont(.rowTitle, style: ZappColors.text)
            }

            Text(store.address)
                .zappFont(.mono, style: ZappColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var amountRow: some View {
        HStack {
            Text(localizable: .sendAmount)
                .zappFont(.body, style: ZappColors.textMuted)

            Spacer()

            ZatoshiRepresentationView(
                balance: store.amount,
                fontName: FontFamily.Inter.semiBold.name,
                mostSignificantFontSize: 14,
                leastSignificantFontSize: 7,
                format: .expanded
            )
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

    private var memo: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappSectionLabel(text: String(localizable: .sendMessage))

            Text(store.message)
                .zappFont(.body, style: ZappColors.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Design.Spacing._lg)
                .background(ZappColors.surfaceInput.color(colorScheme))
        }
    }
}

#Preview {
    NavigationView {
        SendConfirmationView(
            store: SendConfirmation.initial,
            tokenName: "ZEC"
        )
    }
}

// MARK: - Store

extension SendConfirmation {
    @MainActor static var initial = StoreOf<SendConfirmation>(
        initialState: .initial
    ) {
        SendConfirmation()
    }
}

// MARK: - Placeholders

extension SendConfirmation.State {
    static var initial: SendConfirmation.State {
        SendConfirmation.State(
            address: "",
            amount: .zero,
            feeRequired: .zero,
            message: "",
            proposal: nil
        )
    }
}
