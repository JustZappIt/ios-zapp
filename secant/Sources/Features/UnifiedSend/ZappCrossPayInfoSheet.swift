//
//  ZappCrossPayInfoSheet.swift
//  Zapp
//
//  Android's `CrossPayInfoView` (`A:screen/swap/info/CrossPayInfoView.kt`), opened from the unified send
//  header's (i) in swap mode. It explains what "the recipient gets exactly X" means: which leg NEAR
//  guarantees, and that an under-delivered payment is reversed and refunded rather than partially
//  settled. Same copy as the legacy CrossPay help sheet in `SwapAndPayCoordFlowView`.
//

import SwiftUI

struct ZappCrossPayInfoSheet: View {
    private enum Constants {
        static let nearLogoWidth: CGFloat = 98
        static let nearLogoHeight: CGFloat = 24
    }

    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Design.Spacing._md) {
                Text(localizable: .crosspayHelpPayWith)
                    .zappFont(.sectionTitle, style: ZappColors.text)

                Asset.Assets.Partners.nearLogo.image
                    .zImage(
                        width: Constants.nearLogoWidth,
                        height: Constants.nearLogoHeight,
                        style: ZappColors.text
                    )
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
            .padding(.top, Design.Spacing._3xl)
            .padding(.bottom, Design.Spacing._lg)

            VStack(alignment: .leading, spacing: Design.Spacing._xl) {
                Text(localizable: .crosspayHelpDesc1)
                    .zappFont(.body, style: ZappColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                Text(localizable: .crosspayHelpDesc2)
                    .zappFont(.body, style: ZappColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, Design.Spacing._4xl)

            ZappButton(title: String(localizable: .generalOk)) {
                onDismiss()
            }
            .padding(.bottom, Design.Spacing.sheetBottomSpace)
        }
    }
}
