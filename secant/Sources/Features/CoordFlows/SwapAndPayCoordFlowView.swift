//
//  SwapAndPayCoordFlowView.swift
//  Zashi
//
//  Created by Lukáš Korba on 2025-05-14.
//

import SwiftUI
import ComposableArchitecture

struct SwapAndPayCoordFlowView: View {
    @Environment(\.colorScheme) var colorScheme

    private enum Constants {
        static let toolbarIconSize: CGFloat = 22
        static let toolbarTouchTarget: CGFloat = 44
        static let nearLogoWidth: CGFloat = 98
        static let nearLogoHeight: CGFloat = 24
    }

    @Shared(.appStorage(.sensitiveContent)) var isSensitiveContentHidden = false

    @Perception.Bindable var store: StoreOf<SwapAndPayCoordFlow>
    let tokenName: String

    init(store: StoreOf<SwapAndPayCoordFlow>, tokenName: String) {
        self.store = store
        self.tokenName = tokenName
    }

    var body: some View {
        WithPerceptionTracking {
            NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
                SwapAndPayForm(
                    store:
                        store.scope(
                            state: \.swapAndPayState,
                            action: \.swapAndPay
                        ),
                    tokenName: tokenName
                )
                .safeAreaInset(edge: .top, spacing: 0) {
                    WithPerceptionTracking {
                        header
                    }
                }
                .zashiBack(
                    primaryAction: { formPrimaryAction },
                    customDismiss: { store.send(.backButtonTapped) }
                )
            } destination: { store in
                switch store.case {
                case let .addressBook(store):
                    AddressBookView(store: store)
                case let .addressBookContact(store):
                    AddressBookContactView(store: store)
                case let .confirmWithKeystone(store):
                    SignWithKeystoneView(store: store, tokenName: tokenName)
                case let .crossPayConfirmation(store):
                    CrossPayConfirmationView(store: store, tokenName: tokenName)
                case let .preSendingFailure(store):
                    PreSendingFailureView(store: store, tokenName: tokenName)
                case let .scan(store):
                    ScanView(store: store)
                case let .sending(store):
                    SendingView(store: store, tokenName: tokenName)
                case let .sendResultFailure(store):
                    FailureView(store: store, tokenName: tokenName)
                case let .sendResultPending(store):
                    PendingView(store: store, tokenName: tokenName)
                case let .sendResultSuccess(store):
                    SuccessView(store: store, tokenName: tokenName)
                case let .swapAndPayForm(store):
                    SwapAndPayForm(store: store, tokenName: tokenName)
                case let .swapAndPayOptInForced(store):
                    SwapAndPayOptInForcedView(store: store)
                case let .swapToZecSummary(store):
                    SwapToZecSummaryView(store: store, tokenName: tokenName)
                case let .transactionDetails(store):
                    TransactionDetailsView(store: store, tokenName: tokenName)
                }
            }
            .navigationBarHidden(true)
            .zashiSheet(isPresented: $store.isHelpSheetPresented) {
                helpSheetContent()
            }
            .onAppear { store.send(.onAppear) }
            .background(ZappColors.bg.color(colorScheme))
        }
    }

    @ViewBuilder private var formPrimaryAction: some View {
        WithPerceptionTracking {
            if let retryFailure = store.swapAndPayState.swapAssetFailedWithRetry {
                ZappButton(
                    title: retryFailure
                        ? String(localizable: .swapAndPayFailureTryAgain)
                        : String(localizable: .swapAndPayFailureLaterTitle),
                    variant: .danger,
                    isEnabled: retryFailure
                ) {
                    store.send(.swapAndPay(.trySwapsAssetsAgainTapped))
                }
            } else {
                ZappButton(
                    title: store.swapAndPayState.isSwapExperienceEnabled
                        || store.swapAndPayState.isSwapToZecExperienceEnabled
                        ? String(localizable: .swapAndPayGetQuote)
                        : String(localizable: .sendReview),
                    isEnabled: store.swapAndPayState.isValidForm
                        && !store.swapAndPayState.isQuoteRequestInFlight
                ) {
                    store.send(.swapAndPay(.getQuoteTapped))
                }
                .accessibilityIdentifier(
                    store.swapAndPayState.isSwapExperienceEnabled
                        || store.swapAndPayState.isSwapToZecExperienceEnabled
                        ? AccessibilityID.SwapForm.reviewButton
                        : AccessibilityID.CrossPayForm.reviewButton
                )
            }
        }
    }

    private var header: some View {
        ZappScreenHeader(
            title: store.isSwapHelpContent
                ? String(localizable: .swapAndPaySwap)
                : String(localizable: .crosspayTitle),
            containerColor: .bg,
            titleStyle: .displaySecondary,
            left: { EmptyView() },
            right: {
                HStack(spacing: 0) {
                    if store.isSensitiveButtonVisible {
                        Button {
                            $isSensitiveContentHidden.withLock { $0.toggle() }
                        } label: {
                            (isSensitiveContentHidden ? Asset.Assets.eyeOff.image : Asset.Assets.eyeOn.image)
                                .zImage(
                                    width: Constants.toolbarIconSize,
                                    height: Constants.toolbarIconSize,
                                    style: ZappColors.text
                                )
                                .frame(width: Constants.toolbarTouchTarget, height: Constants.toolbarTouchTarget)
                        }
                        .buttonStyle(.zappPress)
                    }

                    Button {
                        store.send(.helpSheetRequested)
                    } label: {
                        Asset.Assets.infoCircle.image
                            .zImage(
                                width: Constants.toolbarIconSize,
                                height: Constants.toolbarIconSize,
                                style: ZappColors.text
                            )
                            .frame(width: Constants.toolbarTouchTarget, height: Constants.toolbarTouchTarget)
                    }
                    .buttonStyle(.zappPress)
                }
            }
        )
    }

    @ViewBuilder private func helpSheetContent() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Design.Spacing._md) {
                Text(
                    store.isSwapHelpContent
                    ? String(localizable: .swapAndPayHelpSwapWith)
                    : String(localizable: .crosspayHelpPayWith)
                )
                .zappFont(.sectionTitle, style: ZappColors.text)

                Asset.Assets.Partners.nearLogo.image
                    .zImage(
                        width: Constants.nearLogoWidth,
                        height: Constants.nearLogoHeight,
                        style: ZappColors.text
                    )
            }
            .padding(.top, Design.Spacing._3xl)
            .padding(.bottom, Design.Spacing._lg)

            if store.isSwapHelpContent {
                infoContent(
                    text: String(localizable: .swapAndPayHelpSwapDesc),
                    desc1: String(localizable: .swapAndPayHelpSwapDesc1),
                    desc2: String(localizable: .swapAndPayHelpSwapDesc2)
                )
                .padding(.bottom, Design.Spacing._4xl)
            } else {
                infoContent(
                    text: String(localizable: .crosspayHelpDesc1),
                    desc1: String(localizable: .crosspayHelpDesc2)
                )
                .padding(.bottom, Design.Spacing._4xl)
            }

            ZappButton(title: String(localizable: .generalOk)) {
                store.send(.helpSheetRequested)
            }
            .padding(.bottom, Design.Spacing.sheetBottomSpace)
        }
    }

    @ViewBuilder private func infoContent(
        text: String,
        desc1: String? = nil,
        desc2: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xl) {
            Text(text)
                .zappFont(.body, style: ZappColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            if let desc1 {
                Text(desc1)
                    .zappFont(.body, style: ZappColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let desc2 {
                Text(desc2)
                    .zappFont(.body, style: ZappColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    NavigationView {
        SwapAndPayCoordFlowView(store: SwapAndPayCoordFlow.placeholder, tokenName: "ZEC")
    }
}

// MARK: - Placeholders

extension SwapAndPayCoordFlow.State {
    static var initial: SwapAndPayCoordFlow.State { SwapAndPayCoordFlow.State() }
}

extension SwapAndPayCoordFlow {
    @MainActor static let placeholder = StoreOf<SwapAndPayCoordFlow>(
        initialState: .initial
    ) {
        SwapAndPayCoordFlow()
    }
}
