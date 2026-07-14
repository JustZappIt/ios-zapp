//
//  SwapAndPayOptInForcedView.swift
//  Zashi
//
//  Created by Lukáš Korba on 2025-06-30.
//

import SwiftUI
import ComposableArchitecture

struct SwapAndPayOptInForcedView: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let brandmarkSize: CGFloat = 64
        static let nearLogoWidth: CGFloat = 98
        static let nearLogoHeight: CGFloat = 24
        static let optionMinHeight: CGFloat = 40
    }

    @Perception.Bindable var store: StoreOf<SwapAndPay>

    init(store: StoreOf<SwapAndPay>) {
        self.store = store
    }

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ScrollView {
                    layout()
                }

                Spacer()

                HStack(alignment: .top, spacing: Design.Spacing._lg) {
                    Asset.Assets.infoCircle.image
                        .zImage(width: 20, height: 20, style: ZappColors.textMuted)

                    Text(localizable: .swapAndPayOptInWarn)
                        .zappFont(.caption, style: ZappColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, Design.Spacing._2xl)

                ZappButton(
                    title: String(localizable: .keystoneTransactionRejectGoBack),
                    variant: .ghost
                ) {
                    store.send(.goBackForcedOptInTapped)
                }
                .padding(.bottom, Design.Spacing._lg)
            }
            .padding(.horizontal, Design.Spacing._2xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .zashiBack(
                primaryAction: {
                    ZappButton(
                        title: String(localizable: .generalConfirm),
                        isEnabled: store.optionOneChecked && store.optionTwoChecked
                    ) {
                        store.send(.confirmForcedOptInTapped)
                    }
                },
                customDismiss: { store.send(.customBackRequired) }
            )
        }
    }

    private func header() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Asset.Assets.Brandmarks.brandmarkMax.image
                    .zImage(
                        width: Constants.brandmarkSize,
                        height: Constants.brandmarkSize,
                        style: ZappColors.text
                    )

                Asset.Assets.Tickers.nearChain.image
                    .resizable()
                    .frame(width: Constants.brandmarkSize, height: Constants.brandmarkSize)
                    .padding(.leading, Design.Spacing._lg)

                Spacer()
            }
            .padding(.vertical, Design.Spacing._3xl)

            HStack(spacing: Design.Spacing._sm) {
                Text(localizable: .swapAndPayOptInTitle)
                    .zappFont(.displaySecondary, style: ZappColors.text)

                Asset.Assets.Partners.nearLogo.image
                    .zImage(
                        width: Constants.nearLogoWidth,
                        height: Constants.nearLogoHeight,
                        style: ZappColors.text
                    )
            }
            .padding(.bottom, Design.Spacing._md)

            Text(localizable: .swapAndPayOptInDesc)
                .zappFont(.body, style: ZappColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func layout() -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing._lg) {
            header()
                .padding(.bottom, Design.Spacing._lg)

            optionRow(
                isOn: store.optionOneChecked,
                title: String(localizable: .swapAndPayForcedOptInOptionOne)
            ) {
                store.send(.optionOneTapped)
            }

            optionRow(
                isOn: store.optionTwoChecked,
                title: String(localizable: .swapAndPayForcedOptInOptionTwo)
            ) {
                store.send(.optionTwoTapped)
            }
        }
    }

    private func optionRow(
        isOn: Bool,
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: Design.Spacing._lg) {
            ZappToggle(isOn: isOn, action: action)

            Text(title)
                .zappFont(.rowTitle, style: ZappColors.text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(minHeight: Constants.optionMinHeight)
        .frame(maxWidth: .infinity)
        .padding(Design.Spacing._xl)
        .overlay(
            Rectangle()
                .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}
