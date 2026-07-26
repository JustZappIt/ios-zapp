//
//  ZappUnifiedSendView.swift
//  Zapp
//
//  iOS's counterpart to Android's `UnifiedSendView` (`A:screen/unifiedsend/UnifiedSendView.kt`):
//  ONE send screen for every entry point, whose inline asset selector switches the same screen
//  between a direct ZEC send and a swap. The two halves are driven by the two existing form
//  reducers (`SendForm`, `SwapAndPay`) scoped out of `SendCoordFlow`; `SendCoordFlow.Mode` decides
//  which one is on screen.
//
//  Nothing in this file broadcasts. The CTA either asks `SendForm` for a proposal or asks
//  `SwapAndPay` for a quote; submission happens in `SendConfirmation` further down the flow, which
//  owns the only calls into the transaction-guarded synchronizer closures.
//

import SwiftUI
import ComposableArchitecture

struct ZappUnifiedSendView: View {
    let store: StoreOf<SendCoordFlow>
    let tokenName: String

    init(store: StoreOf<SendCoordFlow>, tokenName: String) {
        self.store = store
        self.tokenName = tokenName
    }

    var body: some View {
        WithPerceptionTracking {
            UnifiedSendContent(
                store: store,
                sendStore: store.scope(state: \.sendFormState, action: \.sendForm),
                swapStore: store.scope(state: \.swapState, action: \.swap),
                tokenName: tokenName
            )
        }
    }
}

// MARK: - Content

private struct UnifiedSendContent: View {
    private enum Constants {
        static let fieldButtonSize: CGFloat = 40
        static let fieldIconSize: CGFloat = 18
        static let memoMinHeight: CGFloat = 155
        static let memoMaxHeight: CGFloat = 300
        static let hintHeight: CGFloat = 40
        static let hintInset: CGFloat = 24
        static let keyboardAccessoryHeight: CGFloat = 38
        static let toolbarIconSize: CGFloat = 24
        static let toolbarTouchTarget: CGFloat = 48
        static let assetIconSize: CGFloat = 24
        static let assetBadgeSize: CGFloat = 14
        static let amountFieldHeight: CGFloat = 40
        static let swapAmountsButtonSize: CGFloat = 36
        static let assetSelectorMaxWidth: CGFloat = 280
    }

    private enum InputID: Hashable {
        case addressBookHint
        case message
    }

    @Environment(\.colorScheme) private var colorScheme

    let store: StoreOf<SendCoordFlow>
    @Perception.Bindable var sendStore: StoreOf<SendForm>
    @Perception.Bindable var swapStore: StoreOf<SwapAndPay>
    let tokenName: String

    @Shared(.appStorage(.sensitiveContent)) private var isSensitiveContentHidden = false

    @State private var keyboardVisible = false

    @FocusState private var isAddressFocused
    @FocusState private var isAmountFocused

    private var isSwap: Bool { store.mode == .swap }

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
                            VStack(alignment: .leading, spacing: 0) {
                                ZappAvailableBalanceHeader(
                                    balance: sendStore.walletBalancesState.totalBalance,
                                    fiatText: sendStore.walletBalancesState.currencyValue.nilIfEmpty,
                                    tokenName: tokenName
                                )
                                .padding(.bottom, Design.Spacing._4xl)

                                sentence(String(localizable: .unifiedSendSentenceIWantToSend))
                                    .padding(.bottom, Design.Spacing._sm)

                                addressField
                                    .padding(.bottom, Design.Spacing._2xl)

                                sentence(String(localizable: .zappWalletAsset))
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.bottom, Design.Spacing._sm)

                                assetSelector
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.bottom, Design.Spacing._2xl)

                                sentence(String(localizable: .unifiedSendSentenceIllPay))
                                    .padding(.bottom, Design.Spacing._sm)

                                amountSection

                                if isSwap {
                                    theyReceiveRow
                                        .padding(.top, Design.Spacing._xl)

                                    slippageRow
                                        .padding(.top, Design.Spacing._2xl)

                                    depositForZecRow
                                        .padding(.top, Design.Spacing._2xl)
                                } else {
                                    memoSection
                                        .padding(.top, Design.Spacing._2xl)
                                }

                                if store.isTopUpFooterVisible {
                                    Text(localizable: .unifiedSendTopUpSubtitle)
                                        .zappFont(.caption, style: ZappColors.textMuted)
                                        .multilineTextAlignment(.center)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity)
                                        .padding(.top, Design.Spacing._2xl)
                                }
                            }
                            .padding(.horizontal, Design.Spacing._2xl)
                            .padding(.top, Design.Spacing._lg)
                            .padding(.bottom, ZappNavBar.pushedFloatingMargin)
                            .onChange(of: isAddressBookHintVisible) { update in
                                withAnimation(ZappMotion.content) {
                                    if update {
                                        value.scrollTo(InputID.addressBookHint, anchor: .top)
                                    }
                                }
                            }
                        }
                    }
                    .trackKeyboardVisibility($keyboardVisible)
                    .onAppear {
                        sendStore.send(.onAppear)
                        swapStore.send(.onAppear)
                        if sendStore.requestsAddressFocus {
                            isAddressFocused = true
                            sendStore.send(.requestsAddressFocusResolved)
                        }
                    }
                    .onDisappear {
                        sendStore.send(.onDisapear)
                        swapStore.send(.onDisappear)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .zashiBack(
                primaryAction: { ctaButton },
                customDismiss: { store.send(.backButtonTapped) }
            )
            .modifier(
                ZecModeSheets(
                    store: sendStore,
                    tokenName: tokenName
                )
            )
            .modifier(
                SwapModeSheets(
                    coordStore: store,
                    store: swapStore,
                    tokenName: tokenName,
                    keyboardVisible: keyboardVisible
                )
            )
            .overlayPreferenceValue(UnknownAddressPreferenceKey.self) { preferences in
                if isAddressFocused && isAddressBookHintVisible {
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
}

// MARK: - Content sections

private extension UnifiedSendContent {
    // MARK: Header

    private var hideBalancesButton: some View {
        Button {
            $isSensitiveContentHidden.withLock { $0.toggle() }
        } label: {
            (isSensitiveContentHidden ? Asset.Assets.eyeOff.image : Asset.Assets.eyeOn.image)
                .zImage(width: Constants.toolbarIconSize, height: Constants.toolbarIconSize, style: ZappColors.text)
                .frame(width: Constants.toolbarTouchTarget, height: Constants.toolbarTouchTarget)
        }
        .buttonStyle(.zappPress)
    }

    /// Android renders the form as a sentence: "I want to send … Asset … I'll pay …".
    private func sentence(_ text: String) -> some View {
        Text(text)
            .zappFont(.caption, style: ZappColors.textMuted)
    }

    // MARK: Address

    private var isAddressBookHintVisible: Bool {
        isSwap ? swapStore.isAddressBookHintVisible : sendStore.isAddressBookHintVisible
    }

    @ViewBuilder private var addressField: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            HStack(spacing: Design.Spacing._md) {
                if isSwap, let contact = swapStore.selectedContact {
                    selectedContactTag(contact.name)

                    Spacer(minLength: 0)
                } else {
                    TextField(
                        isSwap
                            ? String(localizable: .swapToZecAddress(swapStore.selectedAsset?.chainName ?? ""))
                            : String(localizable: .unifiedSendAddressPlaceholder),
                        text: isSwap ? $swapStore.address : sendStore.bindingForAddress
                    )
                    .zappFont(.mono, style: ZappColors.text)
                    .keyboardType(.alphabet)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isAddressFocused)
                    .disabled(isSwap && swapStore.isQuoteRequestInFlight)
                    .accessibilityIdentifier(AccessibilityID.SendForm.zcashAddressField)
                }

                fieldButton(
                    icon: isNotAddressInAddressBook
                        ? Asset.Assets.Icons.userPlus.image
                        : Asset.Assets.Icons.user.image,
                    identifier: AccessibilityID.SendForm.addToContactsButton
                ) {
                    if isSwap {
                        if swapStore.isNotAddressInAddressBook {
                            swapStore.send(.notInAddressBookButtonTapped(swapStore.address))
                        } else {
                            swapStore.send(.addressBookRequested)
                        }
                    } else {
                        if sendStore.isNotAddressInAddressBook {
                            sendStore.send(.addNewContactTapped(sendStore.address))
                        } else {
                            sendStore.send(.addressBookTapped)
                        }
                    }
                }

                fieldButton(
                    icon: Asset.Assets.Icons.qr.image,
                    identifier: AccessibilityID.SendForm.scanButton
                ) {
                    if isSwap {
                        swapStore.send(.scanTapped)
                    } else {
                        sendStore.send(.scanTapped)
                    }
                }
            }
            .padding(Design.Spacing._md)
            .background(ZappColors.surfaceInput.color(colorScheme))
            .id(InputID.addressBookHint)
            .anchorPreference(key: UnknownAddressPreferenceKey.self, value: .bounds) { $0 }

            if !isSwap, let error = sendStore.invalidAddressErrorText {
                Text(error)
                    .zappFont(.caption, style: ZappColors.danger)
            }
        }
    }

    private var isNotAddressInAddressBook: Bool {
        isSwap ? swapStore.isNotAddressInAddressBook : sendStore.isNotAddressInAddressBook
    }

    private func selectedContactTag(_ name: String) -> some View {
        HStack(spacing: Design.Spacing._sm) {
            Text(name)
                .zappFont(.caption, style: ZappColors.text)

            Button {
                swapStore.send(.selectedContactClearTapped)
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

    // MARK: Asset selector

    /// Android's `ZashiAssetCard`: ZEC by default, and picking anything else is what turns the
    /// screen into a swap.
    @ViewBuilder private var assetSelector: some View {
        Button {
            store.send(.assetPickerRequested)
        } label: {
            HStack(spacing: Design.Spacing._xs) {
                if let asset = store.selectedSwapAsset {
                    tokenTicker(asset: asset, colorScheme)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(asset.token)
                            .zappFont(.caption, style: ZappColors.text)

                        Text(asset.chainName)
                            .zappFont(.caption, style: ZappColors.textMuted)
                    }
                    .fixedSize()
                    .minimumScaleFactor(0.7)
                } else {
                    zecTickerLogo

                    Text(tokenName.uppercased())
                        .zappFont(.caption, style: ZappColors.text)
                }

                Asset.Assets.chevronDown.image
                    .zImage(width: 16, height: 16, style: ZappColors.text)
            }
            .padding(.horizontal, Design.Spacing._md)
            .padding(.vertical, Design.Spacing._sm)
            .frame(maxWidth: Constants.assetSelectorMaxWidth)
            .background(ZappColors.surface.color(colorScheme))
            .overlay(
                Rectangle()
                    .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
            )
        }
        .buttonStyle(.zappPress)
        .disabled(isSwap && swapStore.isQuoteRequestInFlight)
        .accessibilityIdentifier(AccessibilityID.SwapForm.assetSelectButton)
    }

    private var zecTickerLogo: some View {
        Asset.Assets.Brandmarks.brandmarkMax.image
            .zImage(width: Constants.assetIconSize, height: Constants.assetIconSize, style: ZappColors.text)
            .overlay(alignment: .bottomTrailing) {
                Asset.Assets.Icons.shieldTickFilled.image
                    .zImage(width: 11, height: 11, style: ZappColors.text)
                    .frame(width: Constants.assetBadgeSize, height: Constants.assetBadgeSize)
                    .background(ZappColors.surface.color(colorScheme))
                    .offset(x: 4, y: 4)
            }
    }

    // MARK: Amount

    /// Android keeps a single amount field plus an "≈" line and a swap affordance, rather than iOS's
    /// two side-by-side inputs.
    @ViewBuilder private var amountSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            HStack(spacing: Design.Spacing._md) {
                HStack(spacing: Design.Spacing._sm) {
                    Text(amountPrefix)
                        .zappFont(.rowTitle, style: amountText.isEmpty ? ZappColors.textMuted : ZappColors.text)

                    TextField("", text: amountBinding, prompt: amountPlaceholder)
                    .zappFont(.rowTitle, style: ZappColors.text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($isAmountFocused)
                    .disabled(isSwap && swapStore.isQuoteRequestInFlight)
                }
                .padding(Design.Spacing._md)
                .frame(maxWidth: .infinity)
                .frame(minHeight: Constants.amountFieldHeight)
                .background(ZappColors.surfaceInput.color(colorScheme))
                .overlay(
                    Rectangle()
                        .strokeBorder(
                            store.isInsufficientFunds ? ZappColors.danger.color(colorScheme) : Color.clear,
                            lineWidth: 1
                        )
                )

                if isAmountSwapAvailable {
                    Button {
                        if isSwap {
                            swapStore.send(.switchInputTapped)
                        } else {
                            store.send(.amountInputSwapped)
                        }
                    } label: {
                        Asset.Assets.Icons.switchHorizontal.image
                            .zImage(width: 16, height: 16, style: ZappColors.text)
                            .rotationEffect(.degrees(90))
                            .frame(width: Constants.swapAmountsButtonSize, height: Constants.swapAmountsButtonSize)
                            .background(ZappColors.surfaceAlt.color(colorScheme))
                    }
                    .buttonStyle(.zappPress)
                    .accessibilityLabel(String(localizable: .unifiedSendSwapAmounts))
                }
            }

            if isAmountSwapAvailable {
                Text(String(localizable: .unifiedSendEstimatedEquivalent(equivalentAmount, equivalentUnit)))
                    .zappFont(.body, style: ZappColors.textSubtle)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, Design.Spacing._sm)
            }

            if let error = amountErrorText {
                Text(error)
                    .zappFont(.caption, style: ZappColors.danger)
            }
        }
    }

    private var isAmountSwapAvailable: Bool {
        if isSwap {
            return swapStore.zecAsset != nil
        }
        return sendStore.isCurrencyConversionEnabled && sendStore.currencyConversion != nil
    }

    private var amountBinding: Binding<String> {
        if isSwap {
            return $swapStore.amountText
        }
        return store.isFiatPrimary ? sendStore.bindingForCurrency : sendStore.bindingForZecAmount
    }

    private var amountText: String {
        if isSwap {
            return swapStore.amountText
        }
        return store.isFiatPrimary ? sendStore.currencyText.data : sendStore.zecAmountText.data
    }

    private var amountPrefix: String {
        if isSwap {
            return swapStore.isInputInUsd ? CurrencyISO4217.usd.symbol : tokenName.uppercased()
        }
        return store.isFiatPrimary ? sendStore.currencySymbol : tokenName.uppercased()
    }

    private var amountPlaceholder: Text {
        Text(zeroPlaceholder)
            .foregroundColor(ZappColors.textSubtle.color(colorScheme))
    }

    private var zeroPlaceholder: String {
        isSwap ? swapStore.localePlaceholder : swapStore.zeroPlaceholder
    }

    private var equivalentAmount: String {
        if isSwap {
            return swapStore.secondaryLabelFrom
        }
        if store.isFiatPrimary {
            return sendStore.zecAmountText.data.nilIfEmpty ?? swapStore.zeroPlaceholder
        }
        let value = sendStore.currencyText.data.nilIfEmpty ?? swapStore.zeroPlaceholder
        return sendStore.hasCurrencySymbol ? "\(sendStore.currencySymbol)\(value)" : value
    }

    private var equivalentUnit: String {
        if isSwap {
            return swapStore.isInputInUsd ? tokenName.uppercased() : CurrencyISO4217.usd.code
        }
        return store.isFiatPrimary ? tokenName.uppercased() : sendStore.currencyCode
    }

    private var amountErrorText: String? {
        if isSwap {
            return swapStore.isInsufficientFunds ? String(localizable: .sendErrorInsufficientFunds) : nil
        }
        return store.isFiatPrimary
            ? sendStore.invalidCurrencyAmountErrorText
            : sendStore.invalidZecAmountErrorText
    }

    // MARK: Swap-only rows

    private var theyReceiveRow: some View {
        HStack(spacing: Design.Spacing._md) {
            if let asset = swapStore.selectedAsset {
                tokenTicker(asset: asset, colorScheme)

                Text(String(localizable: .unifiedSendTheyReceiveApprox(swapStore.primaryLabelTo, asset.token)))
                    .zappFont(.caption, style: ZappColors.text)

                Spacer(minLength: 0)
            }
        }
    }

    private var slippageRow: some View {
        HStack(spacing: 0) {
            Text(localizable: .swapAndPaySlippageTolerance)
                .zappFont(.body, style: ZappColors.textMuted)

            Spacer()

            Button {
                isAmountFocused = false
                swapStore.send(.slippageTapped)
            } label: {
                HStack(spacing: Design.Spacing._sm) {
                    Text(swapStore.currentSlippageString)
                        .zappFont(.buttonSmall, style: ZappColors.text)

                    Asset.Assets.Icons.settings2.image
                        .zImage(width: 16, height: 16, style: ZappColors.text)
                }
                .padding(.horizontal, Design.Spacing._lg)
                .padding(.vertical, Design.Spacing._md)
                .background(ZappColors.surfaceAlt.color(colorScheme))
            }
            .buttonStyle(.zappPress)
            .disabled(swapStore.isQuoteRequestInFlight)
        }
    }

    /// The opposite direction (deposit another asset, receive ZEC) is not part of Android's unified
    /// screen; it stays in `SwapAndPayCoordFlow` and is reached from here so the corridor keeps an
    /// entry point.
    private var depositForZecRow: some View {
        Button {
            store.send(.swapToZecRequested)
        } label: {
            HStack(spacing: Design.Spacing._md) {
                Asset.Assets.Icons.switchHorizontal.image
                    .zImage(width: 16, height: 16, style: ZappColors.accentText)
                    .rotationEffect(.degrees(90))

                Text(localizable: .unifiedSendDepositToSwapForZec)
                    .zappFont(.caption, style: ZappColors.accentText)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.zappPress)
        .disabled(swapStore.isQuoteRequestInFlight)
    }

    // MARK: Memo

    @ViewBuilder private var memoSection: some View {
        if sendStore.isMemoInputEnabled {
            VStack(alignment: .leading, spacing: Design.Spacing._sm) {
                sentence(String(localizable: .unifiedSendMemoHint))

                MessageEditorView(store: sendStore.memoStore(), isAddUAtoMemoActive: true)
                    .frame(minHeight: Constants.memoMinHeight)
                    .frame(maxHeight: Constants.memoMaxHeight)
                    .id(InputID.message)
            }
        } else {
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

    // MARK: CTA

    @ViewBuilder private var ctaButton: some View {
        WithPerceptionTracking {
            switch store.primaryButton {
            case .topUp:
                ZappButton(title: String(localizable: .unifiedSendTopUp)) {
                    store.send(.topUpRequested)
                }

            case .review, .disabled:
                ZappButton(
                    title: isSwap
                        ? String(localizable: .swapAndPayGetQuote)
                        : String(localizable: .sendReview),
                    isEnabled: store.primaryButton == .review
                ) {
                    if isSwap {
                        swapStore.send(.getQuoteTapped)
                    } else {
                        sendStore.send(.reviewTapped)
                    }
                }
                .accessibilityIdentifier(
                    isSwap ? AccessibilityID.SwapForm.reviewButton : AccessibilityID.SendForm.reviewButton
                )
            }
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
}

// MARK: - Sheets

/// The ZEC-direct sheets, unchanged from `SendFormView`.
private struct ZecModeSheets: ViewModifier {
    @Perception.Bindable var store: StoreOf<SendForm>
    let tokenName: String

    func body(content: Content) -> some View {
        WithPerceptionTracking {
            content
                .zashiSheet(isPresented: $store.isSheetTexAddressVisible) {
                    SendTexAddressHelpSheet(store: store)
                }
                .zashiSheet(isPresented: $store.isCurrencyUnavailableSheetPresented) {
                    SendCurrencyUnavailableSheet(store: store)
                }
                .insufficientFundsSheet(isPresented: $store.isInsufficientBalance)
                .alert(store: store.scope(state: \.$alert, action: \.alert))
                .zashiSheet(isPresented: $store.balancesBinding) {
                    WithPerceptionTracking {
                        BalancesView(
                            store: store.scope(state: \.balancesState, action: \.balances),
                            tokenName: tokenName
                        )
                    }
                }
        }
    }
}

/// The swap sheets, shared verbatim with the swap/cross-pay form (`SwapSheetViews.swift`).
private struct SwapModeSheets: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let coordStore: StoreOf<SendCoordFlow>
    @Perception.Bindable var store: StoreOf<SwapAndPay>
    let tokenName: String
    let keyboardVisible: Bool

    private var assetPickerBinding: Binding<Bool> {
        Binding(
            get: { coordStore.isAssetPickerPresented },
            set: { if !$0 { coordStore.send(.assetPickerDismissed) } }
        )
    }

    func body(content: Content) -> some View {
        WithPerceptionTracking {
            content
                .popover(isPresented: assetPickerBinding) {
                    ZappSwapAssetPickerSheet(
                        store: store,
                        zecRow: ZappSwapAssetPickerSheet.ZecRow(
                            tokenName: tokenName,
                            isSelected: coordStore.mode == .zec,
                            action: { coordStore.send(.zecAssetSelected) }
                        ),
                        onAssetSelected: { coordStore.send(.swapAssetSelected($0)) },
                        onClose: { coordStore.send(.assetPickerDismissed) }
                    )
                    .background(ZappColors.bg.color(colorScheme))
                }
                .zashiSheet(isPresented: $store.isQuotePresented) {
                    ZappSwapQuoteSheet(store: store, tokenName: tokenName)
                }
                .zashiSheet(isPresented: $store.isQuoteUnavailablePresented) {
                    ZappSwapQuoteUnavailableSheet(store: store)
                }
                .zashiSheet(isPresented: $store.isCancelSheetVisible) {
                    ZappSwapCancelSheet(store: store)
                }
                .sheet(isPresented: $store.isSlippagePresented) {
                    ZappSwapSlippageSheet(store: store, keyboardVisible: keyboardVisible)
                        .padding(.horizontal, Design.Spacing._2xl)
                }
                .insufficientFundsSheet(isPresented: $store.isInsufficientBalance)
                .alert(store: store.scope(state: \.$alert, action: \.alert))
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    store.send(.willEnterForeground)
                }
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
