//
//  ZecKeyboardView.swift
//  modules
//
//  Created by Lukáš Korba on 20.09.2024.
//

import SwiftUI
import ComposableArchitecture
@preconcurrency import ZcashLightClientKit

struct ZecKeyboardView: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let keyCount = 12
        static let keySize: CGFloat = 40
        static let keyPadding: CGFloat = 10
        static let keypadHeight: CGFloat = 240
        static let amountHeight: CGFloat = 68
        static let switchIconSize: CGFloat = 20
        static let switchBox: CGFloat = 40
        static let sheetIconBox: CGFloat = 44
        static let sheetIconSize: CGFloat = 20
    }

    @Perception.Bindable var store: StoreOf<ZecKeyboard>

    let tokenName: String

    init(store: StoreOf<ZecKeyboard>, tokenName: String) {
        self.store = store
        self.tokenName = tokenName
    }

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(
                    title: String(localizable: .generalRequest),
                    containerColor: .bg,
                    titleStyle: .displaySecondary,
                    left: { EmptyView() },
                    right: { EmptyView() }
                )

                keyboardBody
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .zashiBack(primaryAction: {
                ZappButton(
                    title: String(localizable: .generalNext),
                    isEnabled: !store.isNextButtonDisabled
                ) {
                    store.send(.nextTapped)
                }
            })
            .zashiSheet(isPresented: $store.isCurrencyUnavailableSheetPresented) {
                currencyUnavailableSheetContent()
            }
        }
    }

    @ViewBuilder private var keyboardBody: some View {
        VStack(spacing: 0) {
            if !store.isValidInput {
                HStack(spacing: Design.Spacing._lg) {
                    Asset.Assets.infoOutline.image
                        .zImage(width: 20, height: 20, style: ZappColors.accentText)

                    Text(localizable: .zecKeyboardInvalid)
                        .zappFont(.caption, style: ZappColors.accentText)

                    Spacer(minLength: 0)
                }
                .padding(Design.Spacing._lg)
                .background(ZappColors.accentSoft.color(colorScheme))
                .padding(.horizontal, Design.Spacing._2xl)
                .padding(.bottom, Design.Spacing._lg)
            }

            mainInput

            if store.currencyConversion != nil {
                convertedInput
                    .padding(.top, Design.Spacing._lg)
            }

            Spacer()

            if store.keys.count == Constants.keyCount {
                keypad
            }
        }
        .padding(.top, Design.Spacing._5xl)
        .onAppear { store.send(.onAppear) }
        .onChange(of: store.currencyConversion) { _ in
            store.send(.validateInputs)
        }
    }

    private var mainInput: some View {
        HStack(spacing: 0) {
            if store.isInputInZec {
                Text(store.humanReadableMainInput)
                + Text(" \(tokenName)")
                    .foregroundColor(ZappColors.textSubtle.color(colorScheme))
            } else {
                if store.isCurrencySymbolPrefix {
                    Text(store.localeCurrencySymbol)
                        .foregroundColor(ZappColors.textSubtle.color(colorScheme))
                    + Text(store.humanReadableMainInput)
                } else {
                    Text(store.humanReadableMainInput)
                    + Text(" \(store.localeCurrencySymbol)")
                        .foregroundColor(ZappColors.textSubtle.color(colorScheme))
                }
            }
        }
        .zappFont(.display, style: ZappColors.text)
        .frame(height: Constants.amountHeight)
        .minimumScaleFactor(0.1)
        .lineLimit(1)
        .padding(.horizontal, Design.Spacing._2xl)
    }

    private var convertedInput: some View {
        HStack(spacing: Design.Spacing._md) {
            Group {
                if store.isInputInZec {
                    if store.isCurrencySymbolPrefix {
                        Text(store.localeCurrencySymbol)
                            .foregroundColor(ZappColors.textSubtle.color(colorScheme))
                        + Text(store.humanReadableConvertedInput)
                    } else {
                        Text(store.humanReadableConvertedInput)
                        + Text(" \(store.localeCurrencySymbol)")
                            .foregroundColor(ZappColors.textSubtle.color(colorScheme))
                    }
                } else {
                    Text(store.humanReadableConvertedInput)
                    + Text(" \(tokenName)")
                        .foregroundColor(ZappColors.textSubtle.color(colorScheme))
                }
            }
            .zappFont(.sectionTitle, style: ZappColors.textMuted)

            Button {
                store.send(.swapCurrenciesTapped)
            } label: {
                Asset.Assets.Icons.switchHorizontal.image
                    .zImage(
                        width: Constants.switchIconSize,
                        height: Constants.switchIconSize,
                        style: ZappColors.text
                    )
                    .rotationEffect(.degrees(90))
                    .frame(width: Constants.switchBox, height: Constants.switchBox)
                    .background(ZappColors.surfaceAlt.color(colorScheme))
            }
            .buttonStyle(.zappPress)
        }
        .minimumScaleFactor(0.6)
        .padding(.horizontal, Design.Spacing._2xl)
    }

    private var keypad: some View {
        VStack(spacing: 0) {
            ForEach(0..<4) { column in
                HStack(spacing: 0) {
                    ForEach(0..<3) { row in
                        WithPerceptionTracking {
                            key(at: column * 3 + row)
                        }
                    }
                }
            }
        }
        .frame(height: Constants.keypadHeight)
        .padding(.bottom, Design.Spacing._3xl)
    }

    private func key(at index: Int) -> some View {
        Button {
            store.send(.keyTapped(index))
        } label: {
            Group {
                if store.keys[index] == "x" {
                    Asset.Assets.Icons.delete.image
                        .zImage(width: Constants.keySize, height: Constants.keySize, style: ZappColors.text)
                } else {
                    Text(store.keys[index])
                        .zappFont(.display, style: ZappColors.text)
                        .frame(width: Constants.keySize, height: Constants.keySize)
                }
            }
            .padding(Constants.keyPadding)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.zappPress)
        .simultaneousGesture(
            LongPressGesture().onEnded { _ in
                if store.keys[index] == "x" {
                    store.send(.longKeyTapped(index))
                }
            }
        )
    }

    @ViewBuilder private func currencyUnavailableSheetContent() -> some View {
        VStack(alignment: .center, spacing: 0) {
            Asset.Assets.Icons.alertOutline.image
                .zImage(
                    width: Constants.sheetIconSize,
                    height: Constants.sheetIconSize,
                    style: ZappColors.danger
                )
                .frame(width: Constants.sheetIconBox, height: Constants.sheetIconBox)
                .background(ZappColors.dangerSoft.color(colorScheme))
                .padding(.top, Design.Spacing._6xl)

            Text(String(localizable: .sendCurrencyUnavailableTitle(store.selectedCurrency.code)))
                .zappFont(.displaySecondary, style: ZappColors.text)
                .multilineTextAlignment(.center)
                .padding(.top, Design.Spacing._3xl)
                .padding(.bottom, Design.Spacing._md)

            Text(String(localizable: .sendCurrencyUnavailableDesc(store.selectedCurrency.displayName)))
                .zappFont(.body, style: ZappColors.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Design.Spacing._3xl)

            ZappButton(title: String(localizable: .sendCurrencyUnavailableSwitchToUSD)) {
                store.send(.currencyUnavailableSwitchToUSDTapped)
            }
            .padding(.bottom, Design.Spacing._md)

            ZappButton(
                title: String(localizable: .sendCurrencyUnavailableContinueInZEC),
                variant: .ghost
            ) {
                store.send(.currencyUnavailableContinueInZECTapped)
            }
            .padding(.bottom, Design.Spacing.sheetBottomSpace)
        }
    }
}

#Preview {
    NavigationView {
        ZecKeyboardView(store: ZecKeyboard.placeholder, tokenName: "ZEC")
    }
}

// MARK: - Placeholders

extension ZecKeyboard.State {
    static var initial: ZecKeyboard.State { ZecKeyboard.State() }
}

extension ZecKeyboard {
    @MainActor static let placeholder = StoreOf<ZecKeyboard>(
        initialState: .initial
    ) {
        ZecKeyboard()
    }
}
