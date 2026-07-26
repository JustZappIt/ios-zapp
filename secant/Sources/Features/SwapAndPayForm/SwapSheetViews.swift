//
//  SwapSheetViews.swift
//  Zapp
//
//  The swap sheets as standalone views so both the swap/cross-pay form
//  (`SwapAndPayForm`) and the unified send form (`ZappUnifiedSendView`) present the *same* sheets
//  instead of each keeping a copy. They were extension methods on `SwapAndPayForm`; the behaviour is
//  unchanged, only the ownership moved.
//

import UIKit
import SwiftUI
import ComposableArchitecture

// MARK: - Asset picker

/// Android's `SwapAssetPickerArgs` screen. The unified send form passes a leading ZEC row, because
/// picking ZEC there is what switches the screen back to a direct ZEC send; the swap/cross-pay form
/// passes none (its ZEC side is fixed).
struct ZappSwapAssetPickerSheet: View {
    struct ZecRow {
        let tokenName: String
        let isSelected: Bool
        let action: () -> Void
    }

    private enum Constants {
        static let assetIconSize: CGFloat = 40
        static let assetBadgeSize: CGFloat = 18
        static let zecBadgeSize: CGFloat = 18
        static let placeholderRows = 15
        static let backdropRows = 5
        static let emptyIllustrationSize: CGFloat = 164
    }

    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<SwapAndPay>
    let zecRow: ZecRow?
    let onAssetSelected: (SwapAsset) -> Void
    let onClose: () -> Void

    init(
        store: StoreOf<SwapAndPay>,
        zecRow: ZecRow? = nil,
        onAssetSelected: @escaping (SwapAsset) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.store = store
        self.zecRow = zecRow
        self.onAssetSelected = onAssetSelected
        self.onClose = onClose
    }

    var body: some View {
        WithPerceptionTracking {
            VStack(alignment: .leading, spacing: 0) {
                ZappScreenHeader(
                    title: String(localizable: .swapAndPaySelectToken),
                    containerColor: .bg,
                    titleStyle: .displaySecondary,
                    left: { EmptyView() },
                    right: {
                        Button(action: onClose) {
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

                if let zecRow, store.searchTerm.isEmpty {
                    zecAssetRow(zecRow)
                }

                if store.swapAssetFailedWithRetry != nil {
                    assetsFailureComposition
                } else if store.swapAssetsToPresent.isEmpty && !store.searchTerm.isEmpty {
                    assetsEmptyComposition
                } else if store.swapAssetsToPresent.isEmpty && store.searchTerm.isEmpty {
                    assetsLoadingComposition
                } else {
                    List {
                        WithPerceptionTracking {
                            ForEach(store.swapAssetsToPresent, id: \.self) { asset in
                                assetView(asset)
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

// MARK: Asset picker rows & states

extension ZappSwapAssetPickerSheet {
    @ViewBuilder private func zecAssetRow(_ row: ZecRow) -> some View {
        VStack(spacing: 0) {
            Button(action: row.action) {
                HStack(spacing: Design.Spacing._lg) {
                    Asset.Assets.Brandmarks.brandmarkMax.image
                        .zImage(
                            width: Constants.assetIconSize,
                            height: Constants.assetIconSize,
                            style: ZappColors.text
                        )
                        .overlay(alignment: .bottomTrailing) {
                            Asset.Assets.Icons.shieldTickFilled.image
                                .zImage(width: 12, height: 12, style: ZappColors.text)
                                .frame(width: Constants.zecBadgeSize, height: Constants.zecBadgeSize)
                                .background(ZappColors.bg.color(colorScheme))
                                .offset(x: 5, y: 5)
                        }

                    VStack(alignment: .leading, spacing: Design.Spacing._xxs) {
                        Text(row.tokenName.uppercased())
                            .zappFont(.rowTitle, style: ZappColors.text)

                        Text(localizable: .swapAndPayQuoteZashi)
                            .zappFont(.rowSubtitle, style: ZappColors.textMuted)
                    }

                    Spacer(minLength: 2)

                    Asset.Assets.chevronRight.image
                        .zImage(width: 18, height: 18, style: ZappColors.textSubtle)
                }
                .padding(.vertical, Design.Spacing._lg)
                .padding(.horizontal, Design.Spacing._2xl)
                .contentShape(Rectangle())
            }
            .buttonStyle(.zappPress)

            Rectangle()
                .fill(ZappColors.border.color(colorScheme))
                .frame(height: 1)
        }
        .background(row.isSelected ? ZappColors.surfaceAlt.color(colorScheme) : ZappColors.bg.color(colorScheme))
    }

    @ViewBuilder private func assetView(_ asset: SwapAsset) -> some View {
        WithPerceptionTracking {
            Button {
                onAssetSelected(asset)
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

    @ViewBuilder private var assetsLoadingComposition: some View {
        List {
            WithPerceptionTracking {
                ForEach(0..<Constants.placeholderRows, id: \.self) { _ in
                    NoTransactionPlaceholder(true)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(ZappColors.bg.color(colorScheme))
                        .listRowSeparator(.hidden)
                }
            }
        }
        .disabled(true)
        .background(ZappColors.bg.color(colorScheme))
        .listStyle(.plain)
    }

    @ViewBuilder private var assetsEmptyComposition: some View {
        WithPerceptionTracking {
            placeholderBackdrop {
                VStack(spacing: 0) {
                    Asset.Assets.Illustrations.emptyState.image
                        .resizable()
                        .frame(width: Constants.emptyIllustrationSize, height: Constants.emptyIllustrationSize)
                        .padding(.bottom, Design.Spacing._2xl)

                    Text(localizable: .swapAndPayEmptyAssetsTitle)
                        .zappFont(.sectionTitle, style: ZappColors.text)
                        .padding(.bottom, Design.Spacing._md)

                    Text(localizable: .swapAndPayEmptyAssetsSubtitle)
                        .zappFont(.body, style: ZappColors.textMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, Design.Spacing._5xl)
            }
        }
    }

    @ViewBuilder private var assetsFailureComposition: some View {
        WithPerceptionTracking {
            placeholderBackdrop {
                VStack(alignment: .center, spacing: 0) {
                    Asset.Assets.Illustrations.cone.image
                        .zImage(
                            width: Constants.emptyIllustrationSize,
                            height: Constants.emptyIllustrationSize,
                            style: ZappColors.text
                        )
                        .padding(.bottom, Design.Spacing._2xl)

                    Text(localizable: .swapAndPayFailureWrong)
                        .zappFont(.sectionTitle, style: ZappColors.text)
                        .padding(.bottom, Design.Spacing._md)

                    Text(localizable: .swapAndPayFailureWrongDesc)
                        .zappFont(.body, style: ZappColors.textMuted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Design.Spacing._2xl)
                        .padding(.bottom, Design.Spacing._2xl)

                    if let retryFailure = store.swapAssetFailedWithRetry, retryFailure {
                        ZappButton(
                            title: String(localizable: .swapAndPayFailureTryAgain),
                            variant: .secondary
                        ) {
                            store.send(.trySwapsAssetsAgainTapped)
                        }
                        .padding(.horizontal, Design.Spacing._6xl)
                    }
                }
            }
        }
    }

    @ViewBuilder private func placeholderBackdrop<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            VStack(spacing: 0) {
                ForEach(0..<Constants.backdropRows, id: \.self) { _ in
                    NoTransactionPlaceholder()
                }

                Spacer()
            }
            .overlay {
                LinearGradient(
                    stops: [
                        Gradient.Stop(color: .clear, location: 0.0),
                        Gradient.Stop(color: ZappColors.bg.color(colorScheme), location: 0.3)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            content()
        }
    }
}

// MARK: - Quote

struct ZappSwapQuoteSheet: View {
    @Environment(\.colorScheme) private var colorScheme

    let store: StoreOf<SwapAndPay>
    let tokenName: String

    var body: some View {
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

                SwapQuoteLine(
                    info: store.isSwapExperienceEnabled
                    ? String(localizable: .swapAndPaySwapFrom)
                    : String(localizable: .swapAndPayPayFrom),
                    value: store.selectedWalletAccount?.vendor.name() ?? String(localizable: .swapAndPayQuoteZashi)
                )
                .padding(.bottom, Design.Spacing._lg)

                SwapQuoteLine(
                    info: store.isSwapExperienceEnabled
                    ? String(localizable: .swapAndPaySwapTo)
                    : String(localizable: .swapAndPayPayTo),
                    value: store.address.zip316,
                    addressFont: true
                )
                .padding(.bottom, Design.Spacing._lg)

                SwapQuoteLine(
                    info: String(localizable: .swapAndPayTotalFees),
                    value: "\(store.totalFeesStr) \(tokenName)"
                )

                if !store.isSwapExperienceEnabled {
                    SwapQuoteSubvalue(value: store.totalFeesUsdStr)

                    SwapQuoteLine(
                        info: String(localizable: .swapAndPayMaxSlippage(store.currentSlippageString)),
                        value: "\(store.swapSlippageStr) \(tokenName)"
                    )
                    .padding(.top, Design.Spacing._lg)

                    SwapQuoteSubvalue(value: store.swapSlippageUsdStr)
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

                SwapQuoteSubvalue(value: store.totalZecUsdToBeSpendInQuote)
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
}

struct SwapQuoteLine: View {
    let info: String
    let value: String
    var addressFont = false

    var body: some View {
        HStack(spacing: 0) {
            Text(info)
                .zappFont(.body, style: ZappColors.textMuted)

            Spacer()

            Text(value)
                .zappFont(addressFont ? .mono : .rowTitle, style: ZappColors.text)
        }
    }
}

struct SwapQuoteSubvalue: View {
    let value: String

    var body: some View {
        HStack(spacing: 0) {
            Spacer()

            Text(value)
                .zappFont(.caption, style: ZappColors.textMuted)
        }
    }
}

// MARK: - Quote unavailable

struct ZappSwapQuoteUnavailableSheet: View {
    @Environment(\.colorScheme) private var colorScheme

    let store: StoreOf<SwapAndPay>

    var body: some View {
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
}

// MARK: - Cancel

struct ZappSwapCancelSheet: View {
    @Environment(\.colorScheme) private var colorScheme

    let store: StoreOf<SwapAndPay>

    var body: some View {
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
}

// MARK: - Slippage

struct ZappSwapSlippageSheet: View {
    private enum Constants {
        static let maxAllowedSlippage = "30%"
        static let slippageChipHeight: CGFloat = 36
        static let customFieldCharWidth: CGFloat = 13.0
        static let keyboardBottomSpace: CGFloat = 74
    }

    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<SwapAndPay>
    let keyboardVisible: Bool

    @State private var isSlippageFocused = false

    var body: some View {
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

                slippageSwitcher
                    .padding(.top, Design.Spacing._3xl)

                slippageInfoText
                    .zappFont(.caption, style: slippageWarnTextStyle)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Design.Spacing._xl)
                    .background(slippageWarnBcgColor)
                    .padding(.vertical, Design.Spacing._2xl)

                Spacer()

                if store.slippageInSheet < 2.0 {
                    let defaultSlippage = "\(SwapAndPay.Constants.defaultSlippage)"
                    if let attrText = try? AttributedString(
                        markdown: String(localizable: .swapAndPaySmallSlippageWarn(defaultSlippage, defaultSlippage)),
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
                .padding(.bottom, keyboardVisible ? Constants.keyboardBottomSpace : Design.Spacing.sheetBottomSpace)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Grows the custom-slippage field with its content; the separator does not count as a digit.
    private var customSlippageFieldWidth: CGFloat {
        guard !store.customSlippage.isEmpty else {
            return .infinity
        }
        let hasSeparator = store.customSlippage.contains(".") || store.customSlippage.contains(",")
        let digits = hasSeparator ? store.customSlippage.count - 1 : store.customSlippage.count
        let width = CGFloat(digits) * Constants.customFieldCharWidth
        return hasSeparator ? width + 2.0 : width
    }

    private var slippageWarnBcgColor: Color {
        if store.slippageInSheet <= 2.0 {
            return ZappColors.surfaceAlt.color(colorScheme)
        } else if store.slippageInSheet > 2.0 && store.slippageInSheet <= 3.0 {
            return ZappColors.accentSoft.color(colorScheme)
        } else {
            return ZappColors.dangerSoft.color(colorScheme)
        }
    }

    private var slippageWarnTextStyle: Colorable {
        if store.slippageInSheet <= 2.0 {
            return ZappColors.textMuted
        } else if store.slippageInSheet > 2.0 && store.slippageInSheet <= 3.0 {
            return ZappColors.accentText
        } else {
            return ZappColors.danger
        }
    }

    @ViewBuilder private var slippageSwitcher: some View {
        HStack(spacing: Design.Spacing._xxs) {
            slippageChip(index: 0, text: store.slippage05String)
            slippageChip(index: 1, text: store.slippage1String)
            slippageChip(index: 2, text: store.slippage2String)

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
                    .frame(maxWidth: customSlippageFieldWidth)
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

    @ViewBuilder private var slippageInfoText: some View {
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

    @ViewBuilder private func slippageChip(index: Int, text: String) -> some View {
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
}
