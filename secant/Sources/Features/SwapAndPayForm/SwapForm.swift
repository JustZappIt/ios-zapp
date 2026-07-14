//
//  SwapForm.swift
//  modules
//
//  Created by Lukáš Korba on 28.08.2025.
//

import SwiftUI
import ComposableArchitecture

extension SwapAndPayForm {
    @ViewBuilder func swapFormView(_ colorScheme: ColorScheme) -> some View {
        WithPerceptionTracking {
            ScrollView {
                VStack(spacing: 0) {
                    ZappAvailableBalanceHeader(
                        balance: store.walletBalancesState.totalBalance,
                        fiatText: availableBalanceFiat,
                        tokenName: tokenName
                    )
                    .padding(.top, Design.Spacing._lg)
                    .padding(.bottom, Design.Spacing._3xl)

                    if store.isSwapExperienceEnabled {
                        fromView(colorScheme)

                        dividerView(colorScheme)

                        toView(colorScheme)

                        addressView()
                    } else {
                        toView(colorScheme)

                        addressView()

                        dividerView(colorScheme)

                        fromView(colorScheme)
                    }

                    slippageView()
                        .padding(.top, Design.Spacing._3xl)
                        .padding(.bottom, Design.Spacing._xl)

                    rateView(colorScheme)

                    Spacer(minLength: Design.Spacing._2xl)
                }
                .ignoresSafeArea()
                .frame(minHeight: keyboardVisible ? 0 : safeAreaHeight)
                .padding(.horizontal, Design.Spacing._2xl)
            }
            .trackKeyboardVisibility($keyboardVisible)
            .onChange(of: store.keyboardDismissCounter) { _ in
                isAmountFocused = false
                isAddressFocused = false
            }
            .background(ZappColors.bg.color(colorScheme))
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                store.send(.willEnterForeground)
            }
            .popover(isPresented: $store.assetSelectBinding) {
                assetContent(colorScheme)
                    .background(ZappColors.bg.color(colorScheme))
            }
            .overlayPreferenceValue(UnknownAddressPreferenceKey.self) { preferences in
                if isAddressFocused && store.isAddressBookHintVisible {
                    GeometryReader { geometry in
                        preferences.map {
                            addressBookHint
                                .frame(width: geometry.size.width - 48)
                                .offset(x: 24, y: geometry[$0].minY + geometry[$0].height + 8)
                        }
                    }
                }
            }
            .overlay {
                if keyboardVisible {
                    keyboardDoneAccessory {
                        isAmountFocused = false
                        isAddressFocused = false
                    }
                }
            }
            .sheet(isPresented: $store.isSlippagePresented) {
                slippageContent(colorScheme)
                    .padding(.horizontal, Design.Spacing._2xl)
                    .background(ZappColors.bg.color(colorScheme))
                    .overlay {
                        if keyboardVisible {
                            keyboardDoneAccessory {
                                UIApplication.shared.sendAction(
                                    #selector(UIResponder.resignFirstResponder),
                                    to: nil,
                                    from: nil,
                                    for: nil
                                )
                            }
                        }
                    }
            }
            .zashiSheet(isPresented: $store.isQuotePresented) {
                quoteContent(colorScheme)
            }
            .zashiSheet(isPresented: $store.isQuoteToZecPresented) {
                quoteToZecContent(colorScheme)
            }
            .zashiSheet(isPresented: $store.isQuoteUnavailablePresented) {
                quoteUnavailableContent(colorScheme)
            }
            .zashiSheet(isPresented: $store.isCancelSheetVisible) {
                cancelSheetContent(colorScheme)
            }
            .zashiSheet(isPresented: $store.isRefundAddressExplainerEnabled) {
                refundAddressSheetContent(colorScheme)
            }
        }
        .onAppear {
            store.send(.onAppear)
            if let window = UIApplication.shared.windows.first {
                let safeFrame = window.safeAreaLayoutGuide.layoutFrame
                safeAreaHeight = safeFrame.height
            }
        }
    }

    private var availableBalanceFiat: String? {
        guard let zecAsset = store.zecAsset else { return nil }
        let balance = store.walletBalancesState.totalBalance.decimalValue.decimalValue
        return (balance * zecAsset.usdPrice).formatted(.currency(code: CurrencyISO4217.usd.code))
    }

    @ViewBuilder private func rateView(_ colorScheme: ColorScheme) -> some View {
        HStack(spacing: 0) {
            Text(localizable: .swapAndPayRate)
                .zappFont(.body, style: ZappColors.textMuted)

            Spacer()

            if let rateValue = store.rateToOneZec, let selectedToken = store.selectedAsset?.token {
                Text(localizable: .swapAndPayOneZecRate(rateValue, selectedToken))
                    .zappFont(.rowTitle, style: ZappColors.text)
            } else {
                Rectangle()
                    .fill(ZappColors.surfaceAlt.color(colorScheme))
                    .shimmer(true)
                    .clipShape(Rectangle())
                    .frame(width: 120, height: 18)
            }
        }
    }

    @ViewBuilder private func fromView(_ colorScheme: ColorScheme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                ZappSectionLabel(
                    text: store.isSwapToZecExperienceEnabled
                        ? String(localizable: .swapAndPayTo)
                        : String(localizable: .swapAndPayFrom)
                )

                Spacer()

                if !store.isSwapToZecExperienceEnabled {
                    HStack(spacing: Design.Spacing._xs) {
                        Text(
                            (store.isSensitiveContentHidden && store.spendability != .nothing)
                            ? String(localizable: .swapAndPayMax(String(localizable: .generalHideBalancesMost)))
                            : store.spendability == .nothing
                            ? String(localizable: .swapAndPayMax(""))
                            : String(localizable: .swapAndPayMax(store.maxLabel))
                        )
                        .zappFont(
                            .caption,
                            style: store.isInsufficientFunds ? ZappColors.danger : ZappColors.textMuted
                        )

                        if store.spendability == .nothing {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 11, height: 14)
                        }
                    }
                }
            }
            .padding(.bottom, Design.Spacing._xs)

            HStack(spacing: Design.Spacing._md) {
                zecTicker(colorScheme)
                    .frame(maxWidth: .infinity)

                if store.isSwapExperienceEnabled {
                    amountInput(colorScheme, showsCurrencyPrefix: true)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isAmountFocused = true
                            }
                        }
                } else {
                    HStack(spacing: 0) {
                        Spacer()

                        Text(store.primaryLabelFrom)
                            .zappFont(.displaySecondary, style: ZappColors.textMuted)
                            .multilineTextAlignment(.trailing)
                            .minimumScaleFactor(0.1)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                }
            }
            .padding(.vertical, Design.Spacing._md)

            HStack(spacing: Design.Spacing._md) {
                Spacer()

                Text(store.secondaryLabelFrom)
                    .zappFont(.caption, style: ZappColors.textMuted)

                if store.isSwapExperienceEnabled {
                    switchInputButton(colorScheme)
                }
            }

            if store.isInsufficientFunds && store.isSwapExperienceEnabled {
                HStack {
                    Spacer()

                    Text(localizable: .sendErrorInsufficientFunds)
                        .zappFont(.caption, style: ZappColors.danger)
                }
                .padding(.top, Design.Spacing._sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func toView(_ colorScheme: ColorScheme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZappSectionLabel(
                text: store.isSwapToZecExperienceEnabled
                    ? String(localizable: .swapAndPayFrom)
                    : String(localizable: .swapAndPayTo)
            )
            .padding(.bottom, Design.Spacing._xs)

            HStack(spacing: Design.Spacing._md) {
                HStack(spacing: 0) {
                    Button {
                        store.send(.assetSelectRequested)
                    } label: {
                        ticker(asset: store.selectedAsset, crosspay: false, colorScheme)
                    }
                    .buttonStyle(.zappPress)
                    .accessibilityIdentifier(AccessibilityID.SwapForm.assetSelectButton)

                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .disabled(store.isQuoteRequestInFlight)

                if store.isSwapExperienceEnabled {
                    HStack(spacing: 0) {
                        Spacer()

                        Text(store.primaryLabelTo)
                            .zappFont(.displaySecondary, style: ZappColors.textMuted)
                            .multilineTextAlignment(.trailing)
                            .minimumScaleFactor(0.1)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                } else {
                    amountInput(colorScheme, showsCurrencyPrefix: store.isInputInUsd)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isAmountFocused = true
                            }
                        }
                }
            }
            .padding(.vertical, Design.Spacing._md)

            HStack(spacing: Design.Spacing._md) {
                Spacer()

                Text(store.secondaryLabelTo)
                    .zappFont(.caption, style: ZappColors.textMuted)

                if !store.isSwapExperienceEnabled {
                    switchInputButton(colorScheme)
                }
            }

            if store.isInsufficientFunds && !store.isSwapExperienceEnabled {
                HStack {
                    Spacer()

                    Text(localizable: .sendErrorInsufficientFunds)
                        .zappFont(.caption, style: ZappColors.danger)
                }
                .padding(.top, Design.Spacing._sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func amountInput(_ colorScheme: ColorScheme, showsCurrencyPrefix: Bool) -> some View {
        HStack(spacing: 0) {
            if showsCurrencyPrefix {
                (store.isInputInUsd
                    ? Asset.Assets.Icons.currencyDollar.image
                    : Asset.Assets.Icons.currencyZec.image)
                    .zImage(
                        width: 18,
                        height: 18,
                        style: store.amountText.isEmpty ? ZappColors.textSubtle : ZappColors.text
                    )
            }

            Spacer()

            TextField(
                "",
                text: $store.amountText,
                prompt:
                    Text(isAmountFocused ? "" : store.localePlaceholder)
                        .foregroundColor(ZappColors.textSubtle.color(colorScheme))
            )
            .disabled(store.isQuoteRequestInFlight)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .autocapitalization(.none)
            .autocorrectionDisabled()
            .keyboardType(.decimalPad)
            .zappFont(.displaySecondary, style: ZappColors.text)
            .lineLimit(1)
            .multilineTextAlignment(.trailing)
            .accentColor(ZappColors.accent.color(colorScheme))
            .focused($isAmountFocused)
        }
        .padding(.horizontal, Design.Spacing._md)
        .padding(.vertical, Design.Spacing._xs)
        .background(ZappColors.surfaceInput.color(colorScheme))
        .overlay(
            Rectangle()
                .strokeBorder(
                    store.isInsufficientFunds
                        ? ZappColors.danger.color(colorScheme)
                        : Color.clear,
                    lineWidth: 1
                )
        )
    }

    @ViewBuilder private func switchInputButton(_ colorScheme: ColorScheme) -> some View {
        Button {
            store.send(.switchInputTapped)
        } label: {
            Asset.Assets.Icons.switchHorizontal.image
                .zImage(width: 14, height: 14, style: ZappColors.text)
                .rotationEffect(.degrees(90))
                .frame(width: 28, height: 28)
                .background(ZappColors.surfaceAlt.color(colorScheme))
        }
        .buttonStyle(.zappPress)
    }

    @ViewBuilder private func dividerView(_ colorScheme: ColorScheme) -> some View {
        HStack(spacing: Design.Spacing._md) {
            Rectangle()
                .fill(ZappColors.border.color(colorScheme))
                .frame(height: 1)

            Button {
                store.send(.enableSwapToZecExperience)
            } label: {
                Asset.Assets.Icons.switchHorizontal.image
                    .zImage(width: 18, height: 18, style: ZappColors.text)
                    .rotationEffect(.degrees(90))
                    .frame(width: 36, height: 36)
                    .background(ZappColors.surface.color(colorScheme))
                    .overlay(
                        Rectangle()
                            .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
                    )
            }
            .buttonStyle(.zappPress)
            .accessibilityIdentifier(AccessibilityID.SwapForm.changeModeButton)
            .disabled(store.isQuoteRequestInFlight)

            Rectangle()
                .fill(ZappColors.border.color(colorScheme))
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Design.Spacing._xl)
    }
}
