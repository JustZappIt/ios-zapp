//
//  SwapAndPayForm.swift
//  Zashi
//
//  Created by Lukáš Korba on 2025-05-26.
//

import SwiftUI
import ComposableArchitecture

struct SwapAndPayForm: View {
    @Environment(\.colorScheme) private var colorScheme

    enum InputID: Hashable {
        case addressBookHint
    }

    enum Constants {
        static let maxAllowedSlippage = "30%"

        static let fieldButtonSize: CGFloat = 40
        static let fieldIconSize: CGFloat = 18
        static let addressMinHeight: CGFloat = 44
        static let slippageChipHeight: CGFloat = 36
        static let tickerIconSize: CGFloat = 24
        static let tickerBadgeSize: CGFloat = 14
        static let tickerBadgeBackdrop: CGFloat = 16
        static let assetIconSize: CGFloat = 40
        static let assetBadgeSize: CGFloat = 18
        static let assetBadgeBackdrop: CGFloat = 22
    }

    @State var keyboardVisible: Bool = false

    @FocusState var isAddressFocused
    @FocusState var isAmountFocused
    @FocusState var isUsdFocused
    @State var isSlippageFocused: Bool = false

    @State var safeAreaHeight: CGFloat = 0

    @Perception.Bindable var store: StoreOf<SwapAndPay>
    let tokenName: String

    init(store: StoreOf<SwapAndPay>, tokenName: String) {
        self.store = store
        self.tokenName = tokenName
    }

    var body: some View {
        WithPerceptionTracking {
            if store.isSwapExperienceEnabled || store.isSwapToZecExperienceEnabled {
                swapFormView(colorScheme)
                    .insufficientFundsSheet(isPresented: $store.isInsufficientBalance)
            } else {
                crossPayFormView(colorScheme)
                    .insufficientFundsSheet(isPresented: $store.isInsufficientBalance)
            }
        }
    }

    @ViewBuilder func addressView() -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            Button {
                store.send(.refundAddressTapped)
            } label: {
                HStack(spacing: Design.Spacing._xs) {
                    ZappSectionLabel(
                        text: store.isSwapToZecExperienceEnabled
                            ? String(localizable: .swapToZecRefundAddress)
                            : store.isSwapExperienceEnabled ? String(localizable: .swapAndPayAddress) : ""
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)

                    if store.isSwapToZecExperienceEnabled {
                        Asset.Assets.infoCircle.image
                            .zImage(width: 14, height: 14, style: ZappColors.textMuted)
                    }

                    Spacer()
                }
            }
            .disabled(!store.isSwapToZecExperienceEnabled)

            HStack(spacing: Design.Spacing._md) {
                if let contact = store.selectedContact {
                    selectedContactTag(contact.name)

                    Spacer(minLength: 0)
                } else {
                    TextField(
                        String(localizable: .swapToZecAddress(store.selectedAsset?.chainName ?? "")),
                        text: $store.address
                    )
                    .zappFont(.mono, style: ZappColors.text)
                    .keyboardType(.alphabet)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isAddressFocused)
                    .disabled(store.isQuoteRequestInFlight)
                }

                fieldButton(
                    icon: store.isNotAddressInAddressBook
                        ? Asset.Assets.Icons.userPlus.image
                        : Asset.Assets.Icons.user.image,
                    identifier: AccessibilityID.SwapAndPayForm.addToContactsButton
                ) {
                    if store.isNotAddressInAddressBook {
                        store.send(.notInAddressBookButtonTapped(store.address))
                    } else {
                        store.send(.addressBookRequested)
                    }
                }

                fieldButton(
                    icon: Asset.Assets.Icons.qr.image,
                    identifier: AccessibilityID.SwapAndPayForm.scanButton
                ) {
                    store.send(.scanTapped)
                }
            }
            .padding(Design.Spacing._md)
            .frame(minHeight: Constants.addressMinHeight)
            .background(ZappColors.surfaceInput.color(colorScheme))
            .id(InputID.addressBookHint)
            .anchorPreference(
                key: UnknownAddressPreferenceKey.self,
                value: .bounds
            ) { $0 }
        }
    }

    private func selectedContactTag(_ name: String) -> some View {
        HStack(spacing: Design.Spacing._sm) {
            Text(name)
                .zappFont(.caption, style: ZappColors.text)

            Button {
                store.send(.selectedContactClearTapped)
            } label: {
                Asset.Assets.buttonCloseX.image
                    .zImage(width: 12, height: 12, style: ZappColors.textMuted)
            }
            .buttonStyle(.zappPress)
        }
        .padding(.horizontal, Design.Spacing._md)
        .padding(.vertical, Design.Spacing._xs)
        .background(ZappColors.chipBg.color(colorScheme))
    }

    @ViewBuilder func slippageView() -> some View {
        HStack(spacing: 0) {
            Text(localizable: .swapAndPaySlippageTolerance)
                .zappFont(.body, style: ZappColors.textMuted)

            Spacer()

            Button {
                isAmountFocused = false
                store.send(.slippageTapped)
            } label: {
                HStack(spacing: Design.Spacing._sm) {
                    Text(store.currentSlippageString)
                        .zappFont(.buttonSmall, style: ZappColors.text)

                    Asset.Assets.Icons.settings2.image
                        .zImage(width: 16, height: 16, style: ZappColors.text)
                }
                .padding(.horizontal, Design.Spacing._lg)
                .padding(.vertical, Design.Spacing._md)
                .background(ZappColors.surfaceAlt.color(colorScheme))
            }
            .buttonStyle(.zappPress)
            .disabled(store.isQuoteRequestInFlight)
        }
    }

    func fieldButton(icon: Image, identifier: String = "", _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon
                .zImage(
                    width: Constants.fieldIconSize,
                    height: Constants.fieldIconSize,
                    style: ZappColors.text
                )
                .frame(width: Constants.fieldButtonSize, height: Constants.fieldButtonSize)
                .background(ZappColors.surface.color(colorScheme))
                .overlay(
                    Rectangle()
                        .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
                )
        }
        .buttonStyle(.zappPress)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder func zecTicker(_ colorScheme: ColorScheme, shield: Bool = true) -> some View {
        HStack(spacing: Design.Spacing._md) {
            zecTickerLogo(colorScheme, shield: shield)

            Text(tokenName)
                .zappFont(.rowTitle, style: ZappColors.text)

            Spacer()
        }
    }

    @ViewBuilder func zecTickerLogo(_ colorScheme: ColorScheme, shield: Bool = true) -> some View {
        Asset.Assets.Brandmarks.brandmarkMax.image
            .zImage(
                width: Constants.tickerIconSize,
                height: Constants.tickerIconSize,
                style: ZappColors.text
            )
            .overlay(alignment: .bottomTrailing) {
                shieldBadge(shield, colorScheme)
                    .offset(x: 4, y: 4)
            }
    }

    @ViewBuilder func zecTickerBadge(_ colorScheme: ColorScheme, shield: Bool = true) -> some View {
        zecTickerLogo(colorScheme, shield: shield)
            .scaleEffect(0.8)
    }

    @ViewBuilder private func shieldBadge(_ shield: Bool, _ colorScheme: ColorScheme) -> some View {
        if shield {
            Asset.Assets.Icons.shieldTickFilled.image
                .zImage(width: 11, height: 11, style: ZappColors.text)
                .frame(width: Constants.tickerBadgeSize, height: Constants.tickerBadgeSize)
                .background(ZappColors.bg.color(colorScheme))
        } else {
            Asset.Assets.Icons.shieldOffSolid.image
                .resizable()
                .frame(width: 11, height: 11)
                .frame(width: Constants.tickerBadgeSize, height: Constants.tickerBadgeSize)
                .background(ZappColors.bg.color(colorScheme))
        }
    }

    var addressBookHint: some View {
        HStack(alignment: .center, spacing: Design.Spacing._lg) {
            Asset.Assets.Icons.userPlus.image
                .zImage(width: 20, height: 20, style: ZappColors.accentText)

            Text(localizable: .sendAddressNotInBook)
                .zappFont(.caption, style: ZappColors.accentText)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Design.Spacing._lg)
        .frame(height: 40)
        .background(ZappColors.accentSoft.color(colorScheme))
    }

    func keyboardDoneAccessory(_ dismiss: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Spacer()

            Rectangle()
                .fill(ZappColors.border.color(colorScheme))
                .frame(height: 1)

            HStack {
                Spacer()

                Button(action: dismiss) {
                    Text(String(localizable: .generalDone).uppercased())
                        .zappFont(.chip, style: ZappColors.accentText)
                }
                .buttonStyle(.zappPress)
            }
            .padding(.horizontal, Design.Spacing._2xl)
            .frame(height: 38)
            .frame(maxWidth: .infinity)
            .background(ZappColors.surface.color(colorScheme))
        }
    }

    /// The swap CTA. `swapAssetFailedWithRetry` swaps it for a retry/unavailable block.
    @ViewBuilder func quoteCta(title: String, accessibilityID: String) -> some View {
        if let retryFailure = store.swapAssetFailedWithRetry {
            VStack(spacing: Design.Spacing._md) {
                Asset.Assets.infoOutline.image
                    .zImage(width: 16, height: 16, style: ZappColors.danger)

                Text(retryFailure
                     ? String(localizable: .swapAndPayFailureRetryTitle)
                     : String(localizable: .swapAndPayFailureLaterTitle)
                )
                .zappFont(.rowTitle, style: ZappColors.danger)

                Text(retryFailure
                     ? String(localizable: .swapAndPayFailureRetryDesc)
                     : String(localizable: .swapAndPayFailureLaterDesc)
                )
                .zappFont(.body, style: ZappColors.danger)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                if retryFailure {
                    ZappButton(
                        title: String(localizable: .swapAndPayFailureTryAgain),
                        variant: .danger
                    ) {
                        store.send(.trySwapsAssetsAgainTapped)
                    }
                    .padding(.top, Design.Spacing._lg)
                }
            }
            .padding(.top, Design.Spacing._4xl)
        } else {
            ZappButton(
                title: title,
                isEnabled: store.isValidForm && !store.isQuoteRequestInFlight
            ) {
                store.send(.getQuoteTapped)
            }
            .accessibilityIdentifier(accessibilityID)
            .padding(.top, keyboardVisible ? Design.Spacing._5xl : 0)
        }
    }
}

extension View {
    @ViewBuilder func noBcgTicker(asset: SwapAsset?, crosspay: Bool, _ colorScheme: ColorScheme) -> some View {
        HStack(spacing: Design.Spacing._xs) {
            if let asset {
                tokenTicker(asset: asset, colorScheme)

                if crosspay {
                    HStack(spacing: Design.Spacing._xs) {
                        Text(asset.token)
                            .zappFont(.rowTitle, style: ZappColors.text)

                        Text(localizable: .tokenOnChain)
                            .zappFont(.body, style: ZappColors.textMuted)

                        Text(asset.chainName)
                            .zappFont(.body, style: ZappColors.textMuted)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(asset.token)
                            .zappFont(.caption, style: ZappColors.text)

                        Text(asset.chainName)
                            .zappFont(.caption, style: ZappColors.textMuted)
                    }
                    .fixedSize()
                    .minimumScaleFactor(0.7)
                }
            } else {
                Rectangle()
                    .fill(ZappColors.surfaceAlt.color(colorScheme))
                    .shimmer(true)
                    .clipShape(Rectangle())
                    .frame(width: SwapAndPayForm.Constants.tickerIconSize, height: SwapAndPayForm.Constants.tickerIconSize)

                Rectangle()
                    .fill(ZappColors.surfaceAlt.color(colorScheme))
                    .shimmer(true)
                    .clipShape(Rectangle())
                    .frame(width: 50, height: 18)
            }

            Asset.Assets.chevronDown.image
                .zImage(width: 16, height: 16, style: ZappColors.text)
        }
        .padding(.horizontal, Design.Spacing._md)
        .padding(.vertical, Design.Spacing._sm)
    }

    @ViewBuilder func tokenTicker(asset: SwapAsset?, _ colorScheme: ColorScheme) -> some View {
        if let asset {
            asset.tokenIcon
                .resizable()
                .frame(
                    width: SwapAndPayForm.Constants.tickerIconSize,
                    height: SwapAndPayForm.Constants.tickerIconSize
                )
                .overlay(alignment: .bottomTrailing) {
                    asset.chainIcon
                        .resizable()
                        .frame(
                            width: SwapAndPayForm.Constants.tickerBadgeSize,
                            height: SwapAndPayForm.Constants.tickerBadgeSize
                        )
                        .background(ZappColors.bg.color(colorScheme))
                        .offset(x: 4, y: 4)
                }
        }
    }

    @ViewBuilder func tokenTickerSelector(asset: SwapAsset?, _ colorScheme: ColorScheme) -> some View {
        if let asset {
            tokenTicker(asset: asset, colorScheme)
                .scaleEffect(0.8)
        }
    }

    @ViewBuilder func ticker(asset: SwapAsset?, crosspay: Bool, _ colorScheme: ColorScheme) -> some View {
        noBcgTicker(asset: asset, crosspay: crosspay, colorScheme)
            .background(ZappColors.surface.color(colorScheme))
            .overlay(
                Rectangle()
                    .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
            )
    }
}

#Preview {
    NavigationView {
        SwapAndPayForm(store: SwapAndPay.initial, tokenName: "ZEC")
    }
}

// MARK: Placeholders

extension SwapAndPay.State {
    static var initial: Self {
        .init(
            walletBalancesState: .initial
        )
    }
}

extension SwapAndPay {
    @MainActor static var initial = StoreOf<SwapAndPay>(
        initialState: .initial
    ) {
        SwapAndPay()
    }
}
