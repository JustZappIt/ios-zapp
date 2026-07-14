//
//  SwapComponents.swift
//  modules
//
//  Created by Lukáš Korba on 24.06.2025.
//

import SwiftUI

enum SwapInfoTone {
    case error
    case info
    case warning

    var background: ZappColors {
        switch self {
        case .error: return .dangerSoft
        case .info: return .chipBg
        case .warning: return .accentSoft
        }
    }

    var foreground: ZappColors {
        switch self {
        case .error: return .danger
        case .info: return .textMuted
        case .warning: return .accentText
        }
    }
}

extension TransactionDetailsView {
    @ViewBuilder func reportSwapSheetContent() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Asset.Assets.Icons.alertOutline.image
                .zImage(size: 20, style: ZappColors.danger)
                .frame(width: 44, height: 44)
                .background(ZappColors.dangerSoft.color(colorScheme))
                .padding(.top, 40)

            Text(localizable: .reportSwapTitle)
                .zappFont(.sectionTitle, style: ZappColors.text)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Text(localizable: .reportSwapMsg)
                .zappFont(.body, style: ZappColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .padding(.bottom, 32)

            ZappButton(title: String(localizable: .reportSwapReport)) {
                store.send(.reportSwapTapped)
            }
            .padding(.bottom, Design.Spacing.sheetBottomSpace)
        }
    }

    @ViewBuilder func swapInfoBanner(
        tone: SwapInfoTone,
        title: String,
        @ViewBuilder message: () -> some View
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Asset.Assets.infoOutline.image
                .zImage(size: 20, style: tone.foreground)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .zappFont(.rowTitle, style: tone.foreground)

                message()
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(tone.background.color(colorScheme))
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.bottom, 20)
    }

    @ViewBuilder func swapRefundInfoView() -> some View {
        swapInfoBanner(tone: .warning, title: String(localizable: .swapAndPayRefundTitle)) {
            Text(localizable: .swapAndPayRefundInfo)
                .zappFont(.caption, style: ZappColors.accentText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder func swapProcessingInfoView() -> some View {
        swapInfoBanner(tone: .info, title: String(localizable: .swapAndPayProcessingTitle)) {
            Text(localizable: .swapAndPayProcessingMsg)
                .zappFont(.caption, style: ZappColors.textMuted)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder func swapExpiredOrFailedInfoView(failed: Bool) -> some View {
        swapInfoBanner(
            tone: .error,
            title: failed
            ? String(localizable: .swapAndPayFailedTitle)
            : String(localizable: .swapAndPayExpiredTitle)
        ) {
            Text(failed
                 ? String(localizable: .swapAndPayFailedMsg)
                 : String(localizable: .swapAndPayExpiredMsg)
            )
            .zappFont(.caption, style: ZappColors.danger)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder func swapIncompleteInfoView() -> some View {
        swapInfoBanner(tone: .warning, title: String(localizable: .swapAndPayStatusIncompleteDeposit)) {
            if let incompleteSwapData = store.incompleteSwapData {
                if let attrText = try? AttributedString(
                    markdown: String(localizable: .swapAndPayIncompleteInfo(
                        incompleteSwapData.missingFunds,
                        incompleteSwapData.tokenName,
                        incompleteSwapData.date
                    )),
                    including: \.zashiApp
                ) {
                    ZashiText(
                        withAttributedString: attrText,
                        colorScheme: colorScheme,
                        textColor: ZappColors.accentText.color(colorScheme),
                        textSize: 12
                    )
                    .zappFont(.caption, style: ZappColors.accentText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// Swap assets panel
extension TransactionDetailsView {
    @ViewBuilder func swapAssetsView() -> some View {
        ZStack {
            HStack(spacing: 1) {
                VStack(alignment: .leading, spacing: 0) {
                    swapAssetsLeftSideView()
                }
                .padding(.horizontal, Design.Spacing._xl)
                .frame(height: 128)
                .frame(maxWidth: .infinity)
                .background(ZappColors.surface.color(colorScheme))

                VStack(alignment: .leading, spacing: 0) {
                    swapAssetsRightSideView()
                }
                .padding(.horizontal, Design.Spacing._xl)
                .frame(height: 128)
                .frame(maxWidth: .infinity)
                .background(ZappColors.surface.color(colorScheme))
            }
            .overlay {
                Rectangle()
                    .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
            }

            swapArrow()
        }
        .padding(.horizontal, Constants.horizontalPadding)
    }

    @ViewBuilder func swapArrow() -> some View {
        Asset.Assets.Icons.arrowRight.image
            .zImage(size: 16, style: ZappColors.textMuted)
            .frame(width: 32, height: 32)
            .background(ZappColors.bg.color(colorScheme))
            .overlay {
                Rectangle()
                    .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
            }
    }

    @ViewBuilder func swapAssetsLeftSideView() -> some View {
        if let swapAmountIn = store.swapAmountIn {
            HStack(spacing: 0) {
                if !store.transaction.isSwapToZec {
                    zecTickerLogo(colorScheme)
                        .padding(.trailing, Design.Spacing._xl)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(tokenName.uppercased())
                            .zappFont(.rowTitle, style: ZappColors.text)

                        Text("Zcash")
                            .zappFont(.caption, style: ZappColors.textMuted)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                } else {
                    if let swapFromAsset = store.swapFromAsset {
                        tokenTicker(asset: swapFromAsset, colorScheme)
                            .padding(.trailing, Design.Spacing._xl)

                        VStack(alignment: .leading, spacing: 0) {
                            Text(swapFromAsset.token)
                                .zappFont(.rowTitle, style: ZappColors.text)

                            Text(swapFromAsset.chainName)
                                .zappFont(.caption, style: ZappColors.textMuted)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    } else {
                        unknownTickerLogo(colorScheme)
                            .padding(.trailing, Design.Spacing._xl)

                        VStack(alignment: .leading, spacing: 4) {
                            unknownValue()
                            unknownValue()
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(height: 63)
            .frame(maxWidth: .infinity)

            ZappColors.border.color(colorScheme)
                .frame(height: 1)
                .padding(.trailing, Design.Spacing._xl)

            VStack(alignment: .leading, spacing: 2) {
                Text(
                    store.isSensitiveContentHidden
                    ? String(localizable: .generalHideBalancesMost)
                    : swapAmountIn
                )
                .zappFont(.rowTitle, style: ZappColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.1)

                if let swapAmountInUsd = store.swapAmountInUsd {
                    Text(
                        store.isSensitiveContentHidden
                        ? String(localizable: .generalHideBalancesMost)
                        : swapAmountInUsd
                    )
                    .zappFont(.caption, style: ZappColors.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.1)
                } else {
                    unknownValue()
                }
            }
            .frame(height: 63)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 0) {
                unknownTickerLogo(colorScheme)
                    .padding(.trailing, Design.Spacing._xl)

                VStack(alignment: .leading, spacing: 4) {
                    unknownValue()
                    unknownValue()
                }

                Spacer(minLength: 0)
            }
            .frame(height: 63)
            .frame(maxWidth: .infinity)

            ZappColors.border.color(colorScheme)
                .frame(height: 1)
                .padding(.trailing, Design.Spacing._xl)

            VStack(alignment: .leading, spacing: 4) {
                unknownValue()
                unknownValue()
            }
            .frame(height: 63)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder func swapAssetsRightSideView() -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            if store.transaction.isSwapToZec {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(tokenName.uppercased())
                        .zappFont(.rowTitle, style: ZappColors.text)

                    Text("Zcash")
                        .zappFont(.caption, style: ZappColors.textMuted)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }

                zecTickerLogo(colorScheme, shield: store.isShielded)
                    .padding(.leading, Design.Spacing._xl)
            } else {
                if let swapToAsset = store.swapToAsset {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(swapToAsset.token)
                            .zappFont(.rowTitle, style: ZappColors.text)

                        Text(swapToAsset.chainName)
                            .zappFont(.caption, style: ZappColors.textMuted)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }

                    tokenTicker(asset: swapToAsset, colorScheme)
                        .padding(.leading, Design.Spacing._xl)
                } else {
                    VStack(alignment: .trailing, spacing: 4) {
                        unknownValue()
                        unknownValue()
                    }

                    unknownTickerLogo(colorScheme)
                        .padding(.leading, Design.Spacing._xl)
                }
            }
        }
        .frame(height: 63)
        .frame(maxWidth: .infinity)

        ZappColors.border.color(colorScheme)
            .frame(height: 1)
            .padding(.leading, Design.Spacing._xl)

        VStack(alignment: .trailing, spacing: 2) {
            if let swapAmountOut = store.swapAmountOut {
                Text(
                    store.isSensitiveContentHidden
                    ? String(localizable: .generalHideBalancesMost)
                    : swapAmountOut
                )
                .zappFont(.rowTitle, style: ZappColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.1)
            } else {
                unknownValue()
            }

            if let swapAmountOutUsd = store.swapAmountOutUsd {
                Text(
                    store.isSensitiveContentHidden
                    ? String(localizable: .generalHideBalancesMost)
                    : swapAmountOutUsd
                )
                .zappFont(.caption, style: ZappColors.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.1)
            } else {
                unknownValue()
            }
        }
        .frame(height: 63)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder func tokenTicker(asset: SwapAsset?, _ colorScheme: ColorScheme) -> some View {
        if let asset {
            asset.tokenIcon
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .overlay(alignment: .bottomTrailing) {
                    asset.chainIcon
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .background(ZappColors.surface.color(colorScheme))
                        .offset(x: 4, y: 4)
                }
        }
    }

    @ViewBuilder func zecTickerLogo(_ colorScheme: ColorScheme, shield: Bool = true) -> some View {
        Asset.Assets.Brandmarks.brandmarkMax.image
            .zImage(size: 28, style: ZappColors.text)
            .overlay(alignment: .bottomTrailing) {
                let shieldIcon = shield
                ? Asset.Assets.Icons.shieldTickFilled.image
                : Asset.Assets.Icons.shieldOffSolid.image

                shieldIcon
                    .zImage(size: 13, style: ZappColors.text)
                    .padding(1)
                    .background(ZappColors.surface.color(colorScheme))
                    .offset(x: 4, y: 4)
            }
    }

    @ViewBuilder func unknownTickerLogo(_ colorScheme: ColorScheme) -> some View {
        Rectangle()
            .fill(ZappColors.surfaceAlt.color(colorScheme))
            .shimmer(true)
            .frame(width: 28, height: 28)
    }

    @ViewBuilder func unknownValue() -> some View {
        Rectangle()
            .fill(ZappColors.surfaceAlt.color(colorScheme))
            .shimmer(true)
            .frame(width: 44, height: 16)
    }

    @ViewBuilder func unknownAmount() -> some View {
        Rectangle()
            .fill(ZappColors.surfaceAlt.color(colorScheme))
            .shimmer(true)
            .frame(width: 178, height: 40)
    }

    @ViewBuilder func unknownAsset() -> some View {
        Rectangle()
            .fill(ZappColors.surfaceAlt.color(colorScheme))
            .shimmer(true)
            .frame(width: TransactionDetailsView.Constants.iconSize, height: TransactionDetailsView.Constants.iconSize)
    }
}
