//
//  SwapComponents.swift
//  modules
//
//  Created by Lukáš Korba on 28.08.2025.
//

import UIKit
import SwiftUI
import ComposableArchitecture

extension SwapAndPayForm {
    @ViewBuilder func assetContent(_ colorScheme: ColorScheme) -> some View {
        WithPerceptionTracking {
            VStack(alignment: .leading, spacing: 0) {
                ZappScreenHeader(
                    title: String(localizable: .swapAndPaySelectToken),
                    containerColor: .bg,
                    titleStyle: .displaySecondary,
                    left: { EmptyView() },
                    right: {
                        Button {
                            store.send(.closeAssetsSheetTapped)
                        } label: {
                            Asset.Assets.buttonCloseX.image
                                .zImage(width: 20, height: 20, style: ZappColors.text)
                                .frame(width: 48, height: 48)
                        }
                        .buttonStyle(.zappPress)
                    }
                )

                HStack(spacing: Design.Spacing._md) {
                    Asset.Assets.Icons.search.image
                        .zImage(width: 18, height: 18, style: ZappColors.textMuted)

                    TextField(String(localizable: .swapAndPaySearch), text: $store.searchTerm)
                        .zappFont(.body, style: ZappColors.text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if !store.searchTerm.isEmpty {
                        Button {
                            store.send(.eraseSearchTermTapped)
                        } label: {
                            Asset.Assets.Icons.xClose.image
                                .zImage(width: 16, height: 16, style: ZappColors.textMuted)
                        }
                        .buttonStyle(.zappPress)
                    }
                }
                .padding(Design.Spacing._lg)
                .background(ZappColors.surfaceInput.color(colorScheme))
                .padding(.horizontal, Design.Spacing._2xl)
                .padding(.bottom, Design.Spacing._2xl)

                if store.swapAssetFailedWithRetry != nil {
                    assetsFailureComposition(colorScheme)
                } else if store.swapAssetsToPresent.isEmpty && !store.searchTerm.isEmpty {
                    assetsEmptyComposition(colorScheme)
                } else if store.swapAssetsToPresent.isEmpty && store.searchTerm.isEmpty {
                    assetsLoadingComposition(colorScheme)
                } else {
                    List {
                        WithPerceptionTracking {
                            ForEach(store.swapAssetsToPresent, id: \.self) { asset in
                                assetView(asset, colorScheme)
                                    .listRowInsets(EdgeInsets())
                                    .listRowBackground(ZappColors.bg.color(colorScheme))
                                    .listRowSeparator(.hidden)
                            }
                        }
                    }
                    .background(ZappColors.bg.color(colorScheme))
                    .listStyle(.plain)
                }
            }
        }
    }
}

extension SwapAndPayForm {
    @ViewBuilder private func assetView(_ asset: SwapAsset, _ colorScheme: ColorScheme) -> some View {
        WithPerceptionTracking {
            Button {
                store.send(.assetTapped(asset))
            } label: {
                VStack(spacing: 0) {
                    HStack(spacing: Design.Spacing._lg) {
                        asset.tokenIcon
                            .resizable()
                            .frame(
                                width: Constants.assetIconSize,
                                height: Constants.assetIconSize
                            )
                            .overlay(alignment: .bottomTrailing) {
                                asset.chainIcon
                                    .resizable()
                                    .frame(
                                        width: Constants.assetBadgeSize,
                                        height: Constants.assetBadgeSize
                                    )
                                    .background(ZappColors.bg.color(colorScheme))
                                    .offset(x: 5, y: 5)
                            }

                        VStack(alignment: .leading, spacing: Design.Spacing._xxs) {
                            Text(asset.token)
                                .zappFont(.rowTitle, style: ZappColors.text)

                            Text(asset.chainName)
                                .zappFont(.rowSubtitle, style: ZappColors.textMuted)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer(minLength: 2)

                        Asset.Assets.chevronRight.image
                            .zImage(width: 18, height: 18, style: ZappColors.textSubtle)
                    }
                    .padding(.vertical, Design.Spacing._lg)
                    .padding(.horizontal, Design.Spacing._2xl)
                    .contentShape(Rectangle())

                    if store.swapAssetsToPresent.last != asset {
                        Rectangle()
                            .fill(ZappColors.border.color(colorScheme))
                            .frame(height: 1)
                    }
                }
            }
            .buttonStyle(.zappPress)
        }
    }

    @ViewBuilder func slippageContent(_ colorScheme: ColorScheme) -> some View {
        WithPerceptionTracking {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    store.send(.closeSlippageSheetTapped)
                } label: {
                    Asset.Assets.buttonCloseX.image
                        .zImage(width: 20, height: 20, style: ZappColors.text)
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.zappPress)
                .padding(.vertical, Design.Spacing._lg)

                Text(localizable: .swapAndPaySlippage)
                    .zappFont(.displaySecondary, style: ZappColors.text)
                    .padding(.bottom, Design.Spacing._md)

                Text(localizable: .swapAndPaySlippageDesc)
                    .zappFont(.body, style: ZappColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                slippageSwitcher(colorScheme)
                    .padding(.top, Design.Spacing._3xl)

                slippageInfoText()
                    .zappFont(.caption, style: slippageWarnTextStyle())
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Design.Spacing._xl)
                    .background(slippageWarnBcgColor(colorScheme))
                    .padding(.vertical, Design.Spacing._2xl)

                Spacer()

                if store.slippageInSheet < 2.0 {
                    if let attrText = try? AttributedString(
                        markdown: String(localizable: .swapAndPaySmallSlippageWarn("\(SwapAndPay.Constants.defaultSlippage)", "\(SwapAndPay.Constants.defaultSlippage)")),
                        including: \.zashiApp
                    ) {
                        ZashiText(
                            withAttributedString: attrText,
                            colorScheme: colorScheme,
                            textColor: ZappColors.accentText.color(colorScheme),
                            textSize: 12
                        )
                        .zappFont(.caption, style: ZappColors.accentText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(Design.Spacing._xl)
                        .background(ZappColors.accentSoft.color(colorScheme))
                        .padding(.bottom, Design.Spacing._3xl)
                    }
                }

                ZappButton(
                    title: String(localizable: .generalConfirm),
                    isEnabled: store.slippageInSheet <= 30.0
                ) {
                    store.send(.slippageSetConfirmTapped)
                }
                .padding(.bottom, keyboardVisible ? 74 : Design.Spacing.sheetBottomSpace)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func slippageSwitcher(_ colorScheme: ColorScheme) -> some View {
        HStack(spacing: Design.Spacing._xxs) {
            slippageChip(index: 0, text: store.slippage05String, colorScheme)
            slippageChip(index: 1, text: store.slippage1String, colorScheme)
            slippageChip(index: 2, text: store.slippage2String, colorScheme)

            if store.selectedSlippageChip == 3 {
                HStack(spacing: 0) {
                    Spacer()

                    FocusableTextField(
                        text: $store.customSlippage,
                        isFirstResponder: $isSlippageFocused,
                        placeholder: "%",
                        colorScheme: colorScheme
                    )
                    .multilineTextAlignment(.center)
                    .frame(maxWidth:
                            store.customSlippage.isEmpty
                           ? .infinity
                           : (store.customSlippage.contains(".") || store.customSlippage.contains(","))
                           ? CGFloat(store.customSlippage.count - 1) * 13.0 + 2.0
                           : CGFloat(store.customSlippage.count) * 13.0
                    )
                    .keyboardType(.decimalPad)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isSlippageFocused = true
                        }
                    }

                    if !store.customSlippage.isEmpty {
                        Text("%")
                            .zappFont(.rowTitle, style: ZappColors.text)
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .frame(height: Constants.slippageChipHeight)
                .background(ZappColors.bg.color(colorScheme))
            } else {
                Text(localizable: .swapAndPayCustom)
                    .zappFont(.caption, style: ZappColors.textMuted)
                    .frame(maxWidth: .infinity)
                    .frame(height: Constants.slippageChipHeight)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.send(.slippageChipTapped(3))
                    }
            }
        }
        .padding(Design.Spacing._xs)
        .frame(maxWidth: .infinity)
        .background(ZappColors.surface.color(colorScheme))
        .overlay(
            Rectangle()
                .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
        )
    }

    @ViewBuilder private func slippageInfoText() -> some View {
        if store.isSwapExperienceEnabled || store.isSwapToZecExperienceEnabled {
            if store.slippageInSheet > 30.0 {
                let part2 = Text(localizable: .swapAndPayMaxAllowedSlippage2(Constants.maxAllowedSlippage)).bold()
                Text(localizable: .swapAndPayMaxAllowedSlippage1) + part2 + Text(store.crosspaySlippageWarning)
            } else if let slippageDiff = store.slippageDiff {
                let part2 = Text(localizable: .swapAndPaySlippageSet2a(store.currentSlippageInSheetString, slippageDiff)).bold()
                Text(localizable: .swapAndPaySlippageSet1) + part2 + Text(localizable: .swapAndPaySlippageSet3) + Text(store.crosspaySlippageWarning)
            } else {
                let part2 = Text(localizable: .swapAndPaySlippageSet2b(store.currentSlippageInSheetString)).bold()
                Text(localizable: .swapAndPaySlippageSet1) + part2 + Text(localizable: .swapAndPaySlippageSet3) + Text(store.crosspaySlippageWarning)
            }
        } else {
            if store.slippageInSheet > 30.0 {
                let part2 = Text(localizable: .swapAndPayMaxAllowedSlippage2(Constants.maxAllowedSlippage)).bold()
                Text(localizable: .swapAndPayMaxAllowedSlippage1) + part2 + Text(store.crosspaySlippageWarning)
            } else if let slippageDiff = store.slippageDiff {
                let part2 = Text(localizable: .crosspaySlippageSet2a(store.currentSlippageInSheetString, slippageDiff)).bold()
                Text(localizable: .crosspaySlippageSet1) + part2 + Text(localizable: .crosspaySlippageSet3) + Text(store.crosspaySlippageWarning)
            } else {
                let part2 = Text(localizable: .crosspaySlippageSet2b(store.currentSlippageInSheetString)).bold()
                Text(localizable: .crosspaySlippageSet1) + part2 + Text(localizable: .crosspaySlippageSet3) + Text(store.crosspaySlippageWarning)
            }
        }
    }

    @ViewBuilder private func slippageChip(index: Int, text: String, _ colorScheme: ColorScheme) -> some View {
        let isSelected = store.selectedSlippageChip == index

        Text(text)
            .zappFont(.caption, style: isSelected ? ZappColors.text : ZappColors.textMuted)
            .frame(maxWidth: .infinity)
            .frame(height: Constants.slippageChipHeight)
            .background(isSelected ? ZappColors.bg.color(colorScheme) : .clear)
            .contentShape(Rectangle())
            .onTapGesture {
                store.send(.slippageChipTapped(index))
            }
    }

    @ViewBuilder func quoteUnavailableContent(_ colorScheme: ColorScheme) -> some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Asset.Assets.Icons.alertOutline.image
                    .zImage(width: 20, height: 20, style: ZappColors.danger)
                    .frame(width: 44, height: 44)
                    .background(ZappColors.dangerSoft.color(colorScheme))
                    .padding(.top, Design.Spacing._3xl)
                    .padding(.bottom, Design.Spacing._lg)

                Text(localizable: .swapAndPayQuoteUnavailable)
                    .zappFont(.displaySecondary, style: ZappColors.text)
                    .padding(.bottom, Design.Spacing._md)

                Text(store.quoteUnavailableErrorMsg)
                    .zappFont(.body, style: ZappColors.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Design.Spacing._xl)
                    .padding(.bottom, Design.Spacing._4xl)

                ZappButton(
                    title: (store.isSwapExperienceEnabled || store.isSwapToZecExperienceEnabled)
                        ? String(localizable: .swapAndPayCancelSwap)
                        : String(localizable: .swapAndPayCancelPayment),
                    variant: .danger
                ) {
                    store.send(.cancelPaymentTapped)
                }
                .padding(.bottom, Design.Spacing._md)

                ZappButton(
                    title: (store.isSwapExperienceEnabled || store.isSwapToZecExperienceEnabled)
                        ? String(localizable: .swapAndPayEditSwap)
                        : String(localizable: .swapAndPayEditPayment)
                ) {
                    store.send(.editPaymentTapped)
                }
                .padding(.bottom, Design.Spacing.sheetBottomSpace)
            }
        }
    }

    @ViewBuilder func quoteContent(_ colorScheme: ColorScheme) -> some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Text(
                    store.isSwapExperienceEnabled
                    ? String(localizable: .swapAndPaySwapNow)
                    : String(localizable: .swapAndPayPayNow)
                )
                .zappFont(.displaySecondary, style: ZappColors.text)
                .padding(.vertical, Design.Spacing._3xl)

                SwapFromToView(
                    tokenName: tokenName,
                    zcashNameInQuote: store.zcashNameInQuote,
                    zecToBeSpendInQuote: store.zecToBeSpendInQuote,
                    zecUsdToBeSpendInQuote: store.zecUsdToBeSpendInQuote,
                    selectedAsset: store.selectedAsset,
                    assetNameInQuote: store.assetNameInQuote,
                    tokenToBeReceivedInQuote: store.tokenToBeReceivedInQuote,
                    tokenUsdToBeReceivedInQuote: store.tokenUsdToBeReceivedInQuote
                )
                .padding(.bottom, Design.Spacing._4xl)

                quoteLineContent(
                    store.isSwapExperienceEnabled
                    ? String(localizable: .swapAndPaySwapFrom)
                    : String(localizable: .swapAndPayPayFrom),
                    store.selectedWalletAccount?.vendor.name() ?? String(localizable: .swapAndPayQuoteZashi)
                )
                .padding(.bottom, Design.Spacing._lg)

                quoteLineContent(
                    store.isSwapExperienceEnabled
                    ? String(localizable: .swapAndPaySwapTo)
                    : String(localizable: .swapAndPayPayTo),
                    store.address.zip316,
                    addressFont: true
                )
                .padding(.bottom, Design.Spacing._lg)

                quoteLineContent(String(localizable: .swapAndPayTotalFees), "\(store.totalFeesStr) \(tokenName)")

                if !store.isSwapExperienceEnabled {
                    quoteSubvalue(store.totalFeesUsdStr)

                    quoteLineContent(
                        String(localizable: .swapAndPayMaxSlippage(store.currentSlippageString)),
                        "\(store.swapSlippageStr) \(tokenName)"
                    )
                    .padding(.top, Design.Spacing._lg)

                    quoteSubvalue(store.swapSlippageUsdStr)
                }

                Rectangle()
                    .fill(ZappColors.border.color(colorScheme))
                    .frame(height: 1)
                    .padding(.vertical, Design.Spacing._lg)

                HStack(spacing: 0) {
                    Text(localizable: .swapAndPayTotalAmount)
                        .zappFont(.rowTitle, style: ZappColors.text)

                    Spacer()

                    Text("\(store.totalZecToBeSpendInQuote) \(tokenName)")
                        .zappFont(.rowTitle, style: ZappColors.text)
                }

                quoteSubvalue(store.totalZecUsdToBeSpendInQuote)
                    .padding(.bottom, Design.Spacing._4xl)

                if store.isSwapExperienceEnabled {
                    HStack(alignment: .top, spacing: Design.Spacing._lg) {
                        Asset.Assets.infoOutline.image
                            .zImage(width: 16, height: 16, style: ZappColors.textSubtle)

                        Text(localizable: .swapAndPaySwapQuoteSlippageWarn(store.swapQuoteSlippageUsdStr, store.currentSlippageString))
                            .zappFont(.caption, style: ZappColors.textSubtle)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, Design.Spacing._3xl)
                }

                if store.selectedWalletAccount?.vendor == .keystone {
                    ZappButton(title: String(localizable: .keystoneConfirmSwap)) {
                        store.send(.confirmWithKeystoneTapped)
                    }
                    .padding(.bottom, Design.Spacing.sheetBottomSpace)
                } else {
                    ZappButton(title: String(localizable: .generalConfirm)) {
                        store.send(.confirmButtonTapped)
                    }
                    .padding(.bottom, Design.Spacing.sheetBottomSpace)
                }
            }
        }
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

                quoteLineContent(
                    String(localizable: .swapAndPayTotalFees),
                    "\(store.swapToZecTotalFees) \(store.selectedAsset?.tokenName ?? "")"
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

                quoteSubvalue(store.zecUsdToBeSpendInQuote)
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

    @ViewBuilder private func quoteSubvalue(_ value: String) -> some View {
        HStack(spacing: 0) {
            Spacer()

            Text(value)
                .zappFont(.caption, style: ZappColors.textMuted)
        }
    }

    @ViewBuilder private func quoteLineContent(
        _ info: String,
        _ value: String,
        addressFont: Bool = false
    ) -> some View {
        HStack(spacing: 0) {
            Text(info)
                .zappFont(.body, style: ZappColors.textMuted)

            Spacer()

            Text(value)
                .zappFont(addressFont ? .mono : .rowTitle, style: ZappColors.text)
        }
    }

    @ViewBuilder func cancelSheetContent(_ colorScheme: ColorScheme) -> some View {
        VStack(spacing: 0) {
            Asset.Assets.Icons.logOut.image
                .zImage(width: 20, height: 20, style: ZappColors.danger)
                .frame(width: 44, height: 44)
                .background(ZappColors.dangerSoft.color(colorScheme))
                .padding(.top, Design.Spacing._6xl)
                .padding(.bottom, Design.Spacing._2xl)

            Text(localizable: .swapAndPayCanceltitle)
                .zappFont(.displaySecondary, style: ZappColors.text)
                .padding(.bottom, Design.Spacing._md)

            Text(localizable: .swapAndPayCancelMsg)
                .zappFont(.body, style: ZappColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .padding(.bottom, Design.Spacing._4xl)

            ZappButton(
                title: String(localizable: .swapAndPayCancelSwap),
                variant: .danger
            ) {
                store.send(.cancelSwapTapped)
            }
            .padding(.bottom, Design.Spacing._md)

            ZappButton(title: String(localizable: .swapAndPayCancelDont)) {
                store.send(.dontCancelTapped)
            }
            .padding(.bottom, Design.Spacing.sheetBottomSpace)
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
