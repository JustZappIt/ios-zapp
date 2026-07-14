//
//  SendRejectSheet.swift
//  modules
//
//  Created by Lukáš Korba on 11.02.2025.
//

import SwiftUI
import ComposableArchitecture

extension SignWithKeystoneView {
    @ViewBuilder func rejectSendContent(colorScheme: ColorScheme) -> some View {
        VStack(spacing: 0) {
            Asset.Assets.Icons.arrowUp.image
                .zImage(width: 20, height: 20, style: ZappColors.danger)
                .frame(width: 44, height: 44)
                .background(ZappColors.dangerSoft.color(colorScheme))
                .padding(.top, Design.Spacing._6xl)
                .padding(.bottom, Design.Spacing._2xl)

            Text(localizable: .keystoneTransactionRejectTitle)
                .zappFont(.displaySecondary, style: ZappColors.text)
                .padding(.bottom, Design.Spacing._md)

            Text(localizable: .keystoneTransactionRejectMsg)
                .zappFont(.body, style: ZappColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .padding(.bottom, Design.Spacing._4xl)

            ZappButton(title: String(localizable: .keystoneTransactionRejectGoBack)) {
                store.send(.rejectRequestCanceled)
            }
            .padding(.bottom, Design.Spacing._md)

            ZappButton(
                title: String(localizable: .keystoneTransactionRejectRejectSig),
                variant: .danger
            ) {
                store.send(.rejectTapped)
            }
            .padding(.bottom, Design.Spacing.sheetBottomSpace)
        }
    }
}
