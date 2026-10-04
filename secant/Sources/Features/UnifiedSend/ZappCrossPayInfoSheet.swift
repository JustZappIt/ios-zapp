//
//  ZappCrossPayInfoSheet.swift
//  Zapp
//
//  Android's `CrossPayInfoView.kt`, raised by the (i) in the Send header while the form is in swap
//  mode. Same copy as the legacy SwapAndPay help sheet (`crosspay.help.*`).
//

import SwiftUI

struct ZappCrossPayInfoSheet: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let nearLogoWidth: CGFloat = 98
        static let nearLogoHeight: CGFloat = 24
        static let height: CGFloat = 420
    }

    let onDismiss: () -> Void

    static var detentHeight: CGFloat { Constants.height }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Design.Spacing._md) {
                Text(localizable: .crosspayHelpPayWith)
                    .zappFont(.sectionTitle, style: ZappColors.text)

                Asset.Assets.Partners.nearLogo.image
                    .zImage(width: Constants.nearLogoWidth, height: Constants.nearLogoHeight, style: ZappColors.text)
            }
            .padding(.bottom, Design.Spacing._lg)

            VStack(alignment: .leading, spacing: Design.Spacing._xl) {
                Text(localizable: .crosspayHelpDesc1)
                    .zappFont(.body, style: ZappColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                Text(localizable: .crosspayHelpDesc2)
                    .zappFont(.body, style: ZappColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Design.Spacing._3xl)

            ZappButton(title: String(localizable: .generalOk), action: onDismiss)
                .padding(.bottom, Design.Spacing._xl)
        }
        .padding(.horizontal, Design.Spacing._3xl)
        .padding(.top, Design.Spacing._3xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ZappColors.surface.color(colorScheme))
    }
}
