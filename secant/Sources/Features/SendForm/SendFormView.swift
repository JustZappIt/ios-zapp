//
//  SendFormView.swift
//  Zashi
//
//  Created by Lukáš Korba on 04/25/2022.
//

import SwiftUI
import ComposableArchitecture

struct SendFormView: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum InputID: Hashable {
        case message
        case addressBookHint
    }

    private enum Constants {
        static let fieldButtonSize: CGFloat = 40
        static let fieldIconSize: CGFloat = 18
        static let memoMinHeight: CGFloat = 155
        static let memoMaxHeight: CGFloat = 300
        static let hintHeight: CGFloat = 40
        static let hintInset: CGFloat = 24
        static let keyboardAccessoryHeight: CGFloat = 38
        static let sheetIconBox: CGFloat = 44
        static let sheetIconSize: CGFloat = 20
        static let stepRailWidth: CGFloat = 3
    }

    @State private var keyboardVisible = false

    @Perception.Bindable var store: StoreOf<SendForm>
    let tokenName: String

    @Shared(.appStorage(.sensitiveContent)) var isSensitiveContentHidden = false

    @FocusState private var isAddressFocused
    @FocusState private var isAmountFocused
    @FocusState private var isCurrencyFocused
    @FocusState private var isMemoFocused

    init(store: StoreOf<SendForm>, tokenName: String) {
        self.store = store
        self.tokenName = tokenName
    }

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(
                    title: String(localizable: .generalSend),
                    containerColor: .bg,
                    titleStyle: .displaySecondary,
                    left: { EmptyView() },
                    right: { hideBalancesButton }
                )

                ScrollView {
                    ScrollViewReader { value in
                        WithPerceptionTracking {
                            VStack(alignment: .leading, spacing: Design.Spacing._2xl) {
                                WalletBalancesView(
                                    store: store.scope(
                                        state: \.walletBalancesState,
                                        action: \.walletBalances
                                    ),
                                    tokenName: tokenName,
                                    couldBeHidden: true
                                )

                                addressField
                                amountFields
                                memoField
                            }
                            .padding(.horizontal, Design.Spacing._2xl)
                            .padding(.bottom, ZappNavBar.pushedFloatingMargin)
                            .onChange(of: store.isNotAddressInAddressBook) { update in
                                withAnimation(ZappMotion.content) {
                                    if update {
                                        value.scrollTo(InputID.addressBookHint, anchor: .top)
                                    }
                                }
                            }
                            .onChange(of: isAddressFocused) { update in
                                withAnimation(ZappMotion.content) {
                                    if update && store.isNotAddressInAddressBook {
                                        value.scrollTo(InputID.addressBookHint, anchor: .top)
                                    }
                                }
                            }
                        }
                    }
                    .trackKeyboardVisibility($keyboardVisible)
                    .onAppear {
                        store.send(.onAppear)
                        if store.requestsAddressFocus {
                            isAddressFocused = true
                            store.send(.requestsAddressFocusResolved)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .zashiBack(
                primaryAction: {
                    ZappButton(
                        title: String(localizable: .sendReview),
                        isEnabled: store.isValidForm
                    ) {
                        store.send(.reviewTapped)
                    }
                    .accessibilityIdentifier(AccessibilityID.SendForm.reviewButton)
                },
                customDismiss: { store.send(.dismissRequired) }
            )
            .zashiSheet(isPresented: $store.isSheetTexAddressVisible) {
                helpSheetContent()
            }
            .zashiSheet(isPresented: $store.isCurrencyUnavailableSheetPresented) {
                currencyUnavailableSheetContent()
            }
            .insufficientFundsSheet(isPresented: $store.isInsufficientBalance)
            .alert(store: store.scope(
                state: \.$alert,
                action: \.alert
            ))
            .zashiSheet(isPresented: $store.balancesBinding) {
                balancesContent()
            }
            .overlayPreferenceValue(UnknownAddressPreferenceKey.self) { preferences in
                if isAddressFocused && store.isAddressBookHintVisible {
                    GeometryReader { geometry in
                        preferences.map {
                            addressBookHint
                                .frame(width: geometry.size.width - Constants.hintInset * 2)
                                .offset(
                                    x: Constants.hintInset,
                                    y: geometry[$0].minY + geometry[$0].height
                                )
                        }
                    }
                }
            }
            .overlay {
                if keyboardVisible {
                    keyboardDismissAccessory
                }
            }
        }
    }

    private var hideBalancesButton: some View {
        Button {
            $isSensitiveContentHidden.withLock { $0.toggle() }
        } label: {
            (isSensitiveContentHidden ? Asset.Assets.eyeOff.image : Asset.Assets.eyeOn.image)
                .zImage(width: 24, height: 24, style: ZappColors.text)
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.zappPress)
    }

    private var addressField: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappSectionLabel(text: String(localizable: .sendTo))

            HStack(spacing: Design.Spacing._md) {
                TextField(
                    String(localizable: .sendAddressPlaceholder),
                    text: store.bindingForAddress
                )
                .zappFont(.mono, style: ZappColors.text)
                .keyboardType(.alphabet)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isAddressFocused)
                .submitLabel(.next)
                .onSubmit { isAmountFocused = true }
                .accessibilityIdentifier(AccessibilityID.SendForm.zcashAddressField)

                fieldButton(
                    icon: store.isNotAddressInAddressBook
                        ? Asset.Assets.Icons.userPlus.image
                        : Asset.Assets.Icons.user.image,
                    identifier: AccessibilityID.SendForm.addToContactsButton
                ) {
                    if store.isNotAddressInAddressBook {
                        store.send(.addNewContactTapped(store.address))
                    } else {
                        store.send(.addressBookTapped)
                    }
                }

                fieldButton(
                    icon: Asset.Assets.Icons.qr.image,
                    identifier: AccessibilityID.SendForm.scanButton
                ) {
                    store.send(.scanTapped)
                }
            }
            .padding(Design.Spacing._md)
            .background(ZappColors.surfaceInput.color(colorScheme))
            .id(InputID.addressBookHint)
            .anchorPreference(key: UnknownAddressPreferenceKey.self, value: .bounds) { $0 }

            if let error = store.invalidAddressErrorText {
                Text(error)
                    .zappFont(.caption, style: ZappColors.danger)
            }
        }
    }

    private var amountFields: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappSectionLabel(text: String(localizable: .sendAmount))

            HStack(alignment: .center, spacing: Design.Spacing._md) {
                amountInput(
                    text: store.bindingForZecAmount,
                    placeholder: tokenName.uppercased(),
                    prefix: nil,
                    focus: $isAmountFocused
                )

                if store.isCurrencyConversionEnabled {
                    Asset.Assets.Icons.switchHorizontal.image
                        .zImage(width: 20, height: 20, style: ZappColors.textMuted)

                    amountInput(
                        text: store.bindingForCurrency,
                        placeholder: store.currencyCode,
                        prefix: store.hasCurrencySymbol ? store.currencySymbol : nil,
                        focus: $isCurrencyFocused
                    )
                    .disabled(store.currencyConversion == nil)
                    .opacity(store.currencyConversion == nil ? 0.5 : 1)
                }
            }

            if let error = store.invalidZecAmountErrorText {
                Text(error)
                    .zappFont(.caption, style: ZappColors.danger)
            }

            if let error = store.invalidCurrencyAmountErrorText {
                Text(error)
                    .zappFont(.caption, style: ZappColors.danger)
            }
        }
    }

    private func amountInput(
        text: Binding<String>,
        placeholder: String,
        prefix: String?,
        focus: FocusState<Bool>.Binding
    ) -> some View {
        HStack(spacing: Design.Spacing._xs) {
            if let prefix {
                Text(prefix)
                    .zappFont(.rowTitle, style: ZappColors.textMuted)
            }

            TextField(placeholder, text: text)
                .zappFont(.rowTitle, style: ZappColors.text)
                .keyboardType(.decimalPad)
                .focused(focus)
        }
        .padding(Design.Spacing._md)
        .frame(maxWidth: .infinity)
        .background(ZappColors.surfaceInput.color(colorScheme))
    }

    @ViewBuilder private var memoField: some View {
        if store.isMemoInputEnabled {
            MessageEditorView(store: store.memoStore(), isAddUAtoMemoActive: true)
                .frame(minHeight: Constants.memoMinHeight)
                .frame(maxHeight: Constants.memoMaxHeight)
                .id(InputID.message)
                .focused($isMemoFocused)
        } else {
            VStack(alignment: .leading, spacing: Design.Spacing._xs) {
                ZappSectionLabel(text: String(localizable: .sendMessage))

                HStack(alignment: .top, spacing: Design.Spacing._lg) {
                    Asset.Assets.infoOutline.image
                        .zImage(width: 20, height: 20, style: ZappColors.textMuted)

                    Text(localizable: .sendInfoMemo)
                        .zappFont(.caption, style: ZappColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .padding(Design.Spacing._lg)
                .background(ZappColors.surfaceAlt.color(colorScheme))
            }
        }
    }

    private var addressBookHint: some View {
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
        .frame(height: Constants.hintHeight)
        .background(ZappColors.accentSoft.color(colorScheme))
    }

    private var keyboardDismissAccessory: some View {
        VStack(spacing: 0) {
            Spacer()

            Rectangle()
                .fill(ZappColors.border.color(colorScheme))
                .frame(height: 1)

            HStack {
                Spacer()

                Button {
                    isAmountFocused = false
                    isAddressFocused = false
                    isCurrencyFocused = false
                    isMemoFocused = false
                } label: {
                    Text(String(localizable: .generalDone).uppercased())
                        .zappFont(.chip, style: ZappColors.accentText)
                }
                .buttonStyle(.zappPress)
            }
            .padding(.horizontal, Design.Spacing._2xl)
            .frame(height: Constants.keyboardAccessoryHeight)
            .frame(maxWidth: .infinity)
            .background(ZappColors.surface.color(colorScheme))
        }
    }

    private func fieldButton(icon: Image, identifier: String = "", _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon
                .zImage(width: Constants.fieldIconSize, height: Constants.fieldIconSize, style: ZappColors.text)
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

    @ViewBuilder private func currencyUnavailableSheetContent() -> some View {
        VStack(alignment: .center, spacing: 0) {
            sheetIcon(Asset.Assets.Icons.alertOutline.image, tint: .danger, background: .dangerSoft)
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

    @ViewBuilder private func helpSheetContent() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetIcon(Asset.Assets.Icons.alertOutline.image, tint: .danger, background: .dangerSoft)
                .padding(.top, Design.Spacing._6xl)

            Text(localizable: .texKeystoneTitle)
                .zappFont(.displaySecondary, style: ZappColors.text)
                .padding(.top, Design.Spacing._3xl)
                .padding(.bottom, Design.Spacing._md)

            Group {
                Text(localizable: .texKeystoneWarn1).bold()
                + Text(localizable: .texKeystoneWarn2)
            }
            .zappFont(.body, style: ZappColors.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, Design.Spacing._3xl)

            Text(localizable: .texKeystoneWorkaround)
                .zappFont(.sectionTitle, style: ZappColors.text)
                .padding(.bottom, Design.Spacing._xl)

            texSupportPoint(0)
            texSupportPoint(1)
                .padding(.bottom, Design.Spacing._md)

            ZappButton(title: String(localizable: .texKeystoneGotIt)) {
                store.send(.gotTexSupportTapped)
            }
            .padding(.top, Design.Spacing._4xl)
            .padding(.bottom, Design.Spacing.sheetBottomSpace)
        }
    }

    private func sheetIcon(_ icon: Image, tint: ZappColors, background: ZappColors) -> some View {
        icon
            .zImage(width: Constants.sheetIconSize, height: Constants.sheetIconSize, style: tint)
            .frame(width: Constants.sheetIconBox, height: Constants.sheetIconBox)
            .background(background.color(colorScheme))
    }

    @ViewBuilder private func texSupportPoint(_ index: Int) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                Asset.Assets.Icons.trIn.image
                    .zImage(width: Constants.sheetIconSize, height: Constants.sheetIconSize, style: index == 0 ? ZappColors.onAccent : ZappColors.text)
                    .rotationEffect(.degrees(225 * Double(index)))
                    .frame(width: Constants.sheetIconBox, height: Constants.sheetIconBox)
                    .background(
                        (index == 0 ? ZappColors.accent : ZappColors.surfaceAlt).color(colorScheme)
                    )

                if index == 0 {
                    Rectangle()
                        .fill(ZappColors.border.color(colorScheme))
                        .frame(width: Constants.stepRailWidth)
                        .padding(.vertical, Design.Spacing._xs)
                }
            }
            .padding(.trailing, Design.Spacing._xl)

            VStack(alignment: .leading, spacing: Design.Spacing._xs) {
                ZappSectionLabel(text: String(localizable: .texKeystoneStep("\(index + 1)")))
                    .padding(.vertical, Design.Spacing._xs)
                    .padding(.horizontal, Design.Spacing._sm)
                    .background(ZappColors.chipBg.color(colorScheme))

                Text(index == 0 ? String(localizable: .texKeystoneStep1Title) : String(localizable: .texKeystoneStep2Title))
                    .zappFont(.rowTitle, style: ZappColors.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text(index == 0 ? String(localizable: .texKeystoneStep1Desc) : String(localizable: .texKeystoneStep2Desc))
                    .zappFont(.body, style: ZappColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, Design.Spacing._3xl)
            }
        }
    }
}

// MARK: - Previews

#Preview {
    NavigationView {
        SendFormView(
            store: .init(
                initialState: .init(
                    addMemoState: true,
                    memoState: .initial,
                    walletBalancesState: .initial
                )
            ) {
                SendForm()
            },
            tokenName: "ZEC"
        )
    }
    .navigationViewStyle(.stack)
}

// MARK: - Store

extension StoreOf<SendForm> {
    func memoStore() -> StoreOf<MessageEditor> {
        self.scope(
            state: \.memoState,
            action: \.memo
        )
    }
}

// MARK: - ViewStore

extension StoreOf<SendForm> {
    var bindingForAddress: Binding<String> {
        Binding(
            get: { self.address.data },
            set: { self.send(.addressUpdated($0.redacted)) }
        )
    }

    var bindingForCurrency: Binding<String> {
        Binding(
            get: { self.currencyText.data },
            set: { self.send(.currencyUpdated($0.redacted)) }
        )
    }

    var bindingForZecAmount: Binding<String> {
        Binding(
            get: { self.zecAmountText.data },
            set: { self.send(.zecAmountUpdated($0.redacted)) }
        )
    }
}

// MARK: Placeholders

extension SendForm.State {
    static var initial: Self {
        .init(
            addMemoState: true,
            memoState: .initial,
            walletBalancesState: .initial
        )
    }
}

// #if DEBUG // FIX: Issue #306 - Release build is broken
extension StoreOf<SendForm> {
    static var placeholder: StoreOf<SendForm> {
        StoreOf<SendForm>(
            initialState: .initial
        ) {
            SendForm()
        }
    }
}
// #endif
