//
//  SwapComponents.swift
//  modules
//
//  Created by Lukáš Korba on 28.08.2025.
//
//  The sheet bodies moved to `SwapSheetViews.swift` so the unified send form
//  (`ZappUnifiedSendView`) presents the same sheets. These remain as the swap/cross-pay form's
//  call-site shims.
//

import UIKit
import SwiftUI
import ComposableArchitecture

extension SwapAndPayForm {
    @ViewBuilder func assetContent(_ colorScheme: ColorScheme) -> some View {
        ZappSwapAssetPickerSheet(
            store: store,
            onAssetSelected: { store.send(.assetTapped($0)) },
            onClose: { store.send(.closeAssetsSheetTapped) }
        )
    }

    @ViewBuilder func slippageContent(_ colorScheme: ColorScheme) -> some View {
        ZappSwapSlippageSheet(store: store, keyboardVisible: keyboardVisible)
    }

    @ViewBuilder func quoteUnavailableContent(_ colorScheme: ColorScheme) -> some View {
        ZappSwapQuoteUnavailableSheet(store: store)
    }

    @ViewBuilder func quoteContent(_ colorScheme: ColorScheme) -> some View {
        ZappSwapQuoteSheet(store: store, tokenName: tokenName)
    }

    @ViewBuilder func cancelSheetContent(_ colorScheme: ColorScheme) -> some View {
        ZappSwapCancelSheet(store: store)
    }

    @ViewBuilder func quoteToZecContent(_ colorScheme: ColorScheme) -> some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Text(localizable: .swapToZecReview)
                    .zappFont(.displaySecondary, style: ZappColors.text)
                    .padding(.vertical, Design.Spacing._3xl)

                SwapFromToView(
                    reversed: true,
                    tokenName: tokenName,
                    zcashNameInQuote: store.zcashNameInQuote,
                    zecToBeSpendInQuote: store.tokenToBeReceivedInQuote,
                    zecUsdToBeSpendInQuote: store.tokenUsdToBeReceivedInQuote,
                    selectedAsset: store.selectedAsset,
                    assetNameInQuote: store.assetNameInQuote,
                    tokenToBeReceivedInQuote: store.swapToZecAmountInQuote,
                    tokenUsdToBeReceivedInQuote: store.zecUsdToBeSpendInQuote
                )
                .padding(.bottom, Design.Spacing._4xl)

                SwapQuoteLine(
                    info: String(localizable: .swapAndPayTotalFees),
                    value: "\(store.swapToZecTotalFees) \(store.selectedAsset?.tokenName ?? "")"
                )

                Rectangle()
                    .fill(ZappColors.border.color(colorScheme))
                    .frame(height: 1)
                    .padding(.vertical, Design.Spacing._lg)

                HStack(spacing: 0) {
                    Text(localizable: .swapAndPayTotalAmount)
                        .zappFont(.rowTitle, style: ZappColors.text)

                    Spacer()

                    Text("\(store.swapToZecAmountInQuote) \(store.selectedAsset?.tokenName ?? "")")
                        .zappFont(.rowTitle, style: ZappColors.text)
                }

                SwapQuoteSubvalue(value: store.zecUsdToBeSpendInQuote)
                    .padding(.bottom, Design.Spacing._4xl)

                HStack(alignment: .top, spacing: Design.Spacing._lg) {
                    Asset.Assets.infoOutline.image
                        .zImage(width: 16, height: 16, style: ZappColors.textSubtle)

                    Text(localizable: .swapAndPaySwapQuoteSlippageWarn(store.swapToZecQuoteSlippageUsdStr, store.currentSlippageString))
                        .zappFont(.caption, style: ZappColors.textSubtle)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Design.Spacing._3xl)

                ZappButton(title: String(localizable: .generalConfirm)) {
                    store.send(.confirmToZecButtonTapped)
                }
                .padding(.bottom, Design.Spacing.sheetBottomSpace)
            }
        }
    }

    @ViewBuilder func refundAddressSheetContent(_ colorScheme: ColorScheme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(localizable: .swapToZecRefundAddressTitle)
                .zappFont(.displaySecondary, style: ZappColors.text)
                .padding(.top, Design.Spacing._4xl)
                .padding(.bottom, Design.Spacing._md)

            Text(localizable: .swapToZecRefundAddressMsg1)
                .zappFont(.body, style: ZappColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Design.Spacing._xl)

            Text(localizable: .swapToZecRefundAddressMsg2)
                .zappFont(.body, style: ZappColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Design.Spacing._xl)
                .padding(.bottom, Design.Spacing._4xl)

            ZappButton(title: String(localizable: .generalOk)) {
                store.send(.refundAddressCloseTapped)
            }
            .padding(.bottom, Design.Spacing.sheetBottomSpace)
        }
    }
}
