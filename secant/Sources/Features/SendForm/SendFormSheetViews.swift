//
//  SendFormSheetViews.swift
//  Zapp
//
//  The ZEC-direct send sheets as standalone views so both `SendFormView` (still the scan flow's
//  form) and the unified send form (`ZappUnifiedSendView`) present the same sheets rather than each
//  keeping a copy. Extracted verbatim from `SendFormView`'s private builders.
//

import SwiftUI
import ComposableArchitecture

/// Keystone cannot sign to a TEX address; the sheet explains the two-step workaround.
struct SendTexAddressHelpSheet: View {
    private enum Constants {
        static let sheetIconBox: CGFloat = 44
        static let sheetIconSize: CGFloat = 20
        static let stepRailWidth: CGFloat = 3
    }

    @Environment(\.colorScheme) private var colorScheme

    let store: StoreOf<SendForm>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetIcon(Asset.Assets.Icons.alertOutline.image, tint: .danger, background: .dangerSoft)
                .padding(.top, Design.Spacing._6xl)

            Text(localizable: .texKeystoneTitle)
                .zappFont(.displaySecondary, style: ZappColors.text)
                .padding(.top, Design.Spacing._3xl)
                .padding(.bottom, Design.Spacing._md)

            Group {
                Text(localizable: .texKeystoneWarn1).bold()
                + Text(localizable: .texKeystoneWarn2)
            }
            .zappFont(.body, style: ZappColors.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, Design.Spacing._3xl)

            Text(localizable: .texKeystoneWorkaround)
                .zappFont(.sectionTitle, style: ZappColors.text)
                .padding(.bottom, Design.Spacing._xl)

            texSupportPoint(0)
            texSupportPoint(1)
                .padding(.bottom, Design.Spacing._md)

            ZappButton(title: String(localizable: .texKeystoneGotIt)) {
                store.send(.gotTexSupportTapped)
            }
            .padding(.top, Design.Spacing._4xl)
            .padding(.bottom, Design.Spacing.sheetBottomSpace)
        }
    }

    private func sheetIcon(_ icon: Image, tint: ZappColors, background: ZappColors) -> some View {
        icon
            .zImage(width: Constants.sheetIconSize, height: Constants.sheetIconSize, style: tint)
            .frame(width: Constants.sheetIconBox, height: Constants.sheetIconBox)
            .background(background.color(colorScheme))
    }

    @ViewBuilder private func texSupportPoint(_ index: Int) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                Asset.Assets.Icons.trIn.image
                    .zImage(
                        width: Constants.sheetIconSize,
                        height: Constants.sheetIconSize,
                        style: index == 0 ? ZappColors.onAccent : ZappColors.text
                    )
                    .rotationEffect(.degrees(225 * Double(index)))
                    .frame(width: Constants.sheetIconBox, height: Constants.sheetIconBox)
                    .background(
                        (index == 0 ? ZappColors.accent : ZappColors.surfaceAlt).color(colorScheme)
                    )

                if index == 0 {
                    Rectangle()
                        .fill(ZappColors.border.color(colorScheme))
                        .frame(width: Constants.stepRailWidth)
                        .padding(.vertical, Design.Spacing._xs)
                }
            }
            .padding(.trailing, Design.Spacing._xl)

            VStack(alignment: .leading, spacing: Design.Spacing._xs) {
                ZappSectionLabel(text: String(localizable: .texKeystoneStep("\(index + 1)")))
                    .padding(.vertical, Design.Spacing._xs)
                    .padding(.horizontal, Design.Spacing._sm)
                    .background(ZappColors.chipBg.color(colorScheme))

                Text(index == 0 ? String(localizable: .texKeystoneStep1Title) : String(localizable: .texKeystoneStep2Title))
                    .zappFont(.rowTitle, style: ZappColors.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text(index == 0 ? String(localizable: .texKeystoneStep1Desc) : String(localizable: .texKeystoneStep2Desc))
                    .zappFont(.body, style: ZappColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, Design.Spacing._3xl)
            }
        }
    }
}

/// The selected local currency has no rate: offer USD or continuing in ZEC.
struct SendCurrencyUnavailableSheet: View {
    private enum Constants {
        static let sheetIconBox: CGFloat = 44
        static let sheetIconSize: CGFloat = 20
    }

    @Environment(\.colorScheme) private var colorScheme

    let store: StoreOf<SendForm>

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            Asset.Assets.Icons.alertOutline.image
                .zImage(width: Constants.sheetIconSize, height: Constants.sheetIconSize, style: ZappColors.danger)
                .frame(width: Constants.sheetIconBox, height: Constants.sheetIconBox)
                .background(ZappColors.dangerSoft.color(colorScheme))
                .padding(.top, Design.Spacing._6xl)

            Text(String(localizable: .sendCurrencyUnavailableTitle(store.selectedCurrency.code)))
                .zappFont(.displaySecondary, style: ZappColors.text)
                .multilineTextAlignment(.center)
                .padding(.top, Design.Spacing._3xl)
                .padding(.bottom, Design.Spacing._md)

            Text(String(localizable: .sendCurrencyUnavailableDesc(store.selectedCurrency.displayName)))
                .zappFont(.body, style: ZappColors.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Design.Spacing._3xl)

            ZappButton(title: String(localizable: .sendCurrencyUnavailableSwitchToUSD)) {
                store.send(.currencyUnavailableSwitchToUSDTapped)
            }
            .padding(.bottom, Design.Spacing._md)

            ZappButton(
                title: String(localizable: .sendCurrencyUnavailableContinueInZEC),
                variant: .ghost
            ) {
                store.send(.currencyUnavailableContinueInZECTapped)
            }
            .padding(.bottom, Design.Spacing.sheetBottomSpace)
        }
    }
}
