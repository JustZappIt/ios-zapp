//
//  CrossPayForm.swift
//  modules
//
//  Created by Lukáš Korba on 28.08.2025.
//

import SwiftUI
import ComposableArchitecture

extension SwapAndPayForm {
    @ViewBuilder func crossPayFormView(_ colorScheme: ColorScheme) -> some View {
        WithPerceptionTracking {
            ScrollView {
                VStack(spacing: 0) {
                    WithPerceptionTracking {
                        WalletBalancesView(
                            store: store.scope(
                                state: \.walletBalancesState,
                                action: \.walletBalances
                            ),
                            tokenName: tokenName,
                            couldBeHidden: true
                        )
                        .frame(height: 144)

                        VStack(alignment: .leading, spacing: Design.Spacing._2xl) {
                            assetField(colorScheme)
                            addressView()
                            amountFields(colorScheme)
                            payZecRow(colorScheme)
                            slippageView()
                        }

                        Spacer(minLength: Design.Spacing._2xl)
                    }
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
            .zashiSheet(isPresented: $store.isQuotePresented) {
                quoteContent(colorScheme)
            }
            .zashiSheet(isPresented: $store.isQuoteUnavailablePresented) {
                quoteUnavailableContent(colorScheme)
            }
            .zashiSheet(isPresented: $store.isCancelSheetVisible) {
                cancelSheetContent(colorScheme)
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
            .zashiSheet(isPresented: $store.balancesBinding) {
                WithPerceptionTracking {
                    BalancesView(
                        store:
                            store.scope(
                                state: \.balancesState,
                                action: \.balances
                            ),
                        tokenName: tokenName
                    )
                }
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
                        isUsdFocused = false
                    }
                }
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

    @ViewBuilder private func assetField(_ colorScheme: ColorScheme) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappSectionLabel(text: String(localizable: .sendTo))

            HStack(spacing: 0) {
                Button {
                    store.send(.assetSelectRequested)
                } label: {
                    ticker(asset: store.selectedAsset, crosspay: true, colorScheme)
                }
                .buttonStyle(.zappPress)
                .accessibilityIdentifier(AccessibilityID.CrossPayForm.assetSelectButton)

                Spacer()
            }
        }
    }

    @ViewBuilder private func amountFields(_ colorScheme: ColorScheme) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappSectionLabel(text: String(localizable: .sendAmount))

            HStack(spacing: Design.Spacing._md) {
                crossPayInput(
                    colorScheme,
                    text: $store.amountAssetText,
                    placeholder: store.selectedAsset?.tokenName ?? store.zeroPlaceholder,
                    prefix: nil,
                    focus: $isAmountFocused
                )

                Asset.Assets.Icons.switchHorizontal.image
                    .zImage(width: 20, height: 20, style: ZappColors.textMuted)

                crossPayInput(
                    colorScheme,
                    text: $store.amountUsdText,
                    placeholder: String(localizable: .sendCurrencyPlaceholder),
                    prefix: Asset.Assets.Icons.currencyDollar.image,
                    focus: $isUsdFocused
                )
            }
            .disabled(store.isQuoteRequestInFlight)

            if store.isCrossPayInsufficientFunds {
                Text(localizable: .sendErrorInsufficientFunds)
                    .zappFont(.caption, style: ZappColors.danger)
            }
        }
    }

    private func crossPayInput(
        _ colorScheme: ColorScheme,
        text: Binding<String>,
        placeholder: String,
        prefix: Image?,
        focus: FocusState<Bool>.Binding
    ) -> some View {
        HStack(spacing: Design.Spacing._xs) {
            if let prefix {
                prefix
                    .zImage(width: 18, height: 18, style: ZappColors.textMuted)
            }

            TextField(placeholder, text: text)
                .zappFont(.rowTitle, style: ZappColors.text)
                .keyboardType(.decimalPad)
                .focused(focus)
        }
        .padding(Design.Spacing._md)
        .frame(maxWidth: .infinity)
        .background(ZappColors.surfaceInput.color(colorScheme))
        .overlay(
            Rectangle()
                .strokeBorder(
                    store.isCrossPayInsufficientFunds
                        ? ZappColors.danger.color(colorScheme)
                        : Color.clear,
                    lineWidth: 1
                )
        )
    }

    @ViewBuilder private func payZecRow(_ colorScheme: ColorScheme) -> some View {
        HStack(spacing: Design.Spacing._md) {
            zecTicker(colorScheme)

            Text("\(store.payZecLabel) \(tokenName)")
                .zappFont(
                    .rowTitle,
                    style: store.isCrossPayInsufficientFunds ? ZappColors.danger : ZappColors.text
                )
        }
    }
}
