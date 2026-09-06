// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import SwiftUI

struct OnrampView: View {
    @Environment(\.colorScheme) var colorScheme
    @Perception.Bindable var store: StoreOf<Onramp>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: String(localizable: .onrampTitle)) {
                    Button { store.send(.infoTapped) } label: {
                        Asset.Assets.infoCircle.image
                            .zImage(width: 20, height: 20, style: ZappColors.text)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.zappPress)
                    .accessibilityLabel(String(localizable: .onrampInfoContentDescription))
                }

                ScrollView {
                    pageContent
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                        .padding(.bottom, 28)
                }
                .scrollDismissesKeyboard(.interactively)

                bottomBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .zappDismissKeyboardOnTap()
            .zappSwipeBack { store.send(.backTapped) }
            .onAppear { store.send(.onAppear) }
            .zashiSheet(isPresented: infoBinding) { infoSheet }
            .zashiSheet(isPresented: paidBinding) { paidConfirmationSheet }
            .zashiSheet(isPresented: baseRefundBinding) { baseRefundSheet }
        }
    }

    @ViewBuilder
    var pageContent: some View {
        switch store.page {
        case .loading: loading
        case .unavailable: unavailable
        case .amount: amount
        case .confirmation: confirmation
        case .progress: progress
        case .payment: payment
        case .convertingToZec: converting
        case .completion, .refundedToBase: completion
        case .deliveryNeedsAttention: deliveryNeedsAttention
        }
    }

    /// A bare spinner, as Android's `LoadingContent` has it. This used to carry
    /// `onrampProgressSubtitleWorking` — "Zapp is working through your order. Keep this screen
    /// open." — which belongs to an order already in flight. Opening the screen placed no order,
    /// so it told the user something alarming and untrue.
    var loading: some View {
        ProgressView()
            .tint(ZappColors.accent.color(colorScheme))
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
    }

    var unavailable: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localizable: .onrampUnavailableTitle))
                .zappFont(.screenTitle, style: ZappColors.text)
            Text(store.errorMessage ?? String(localizable: .onrampUnavailableBody))
                .zappFont(.body, style: ZappColors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var bottomBar: some View {
        ZappBottomActionBar(onBack: { store.send(.backTapped) }, isBackEnabled: !store.isSendingBaseBalanceToZec) {
            ZappButton(
                title: primaryTitle,
                variant: store.page == .progress && !store.isSettledAgainstUser ? .danger : .primary,
                isEnabled: primaryEnabled
            ) { primaryTapped() }
        }
    }

    var errorText: some View {
        Group {
            if let error = store.errorMessage {
                Text(error).zappFont(.caption, style: ZappColors.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    func dangerNotice(_ message: String) -> some View {
        ZappBorderedCard(variant: .danger) {
            Text(message).zappFont(.body, style: ZappColors.danger)
        }
    }

    var infoBinding: Binding<Bool> {
        Binding(get: { store.isInfoPresented }, set: { if !$0 { store.send(.infoDismissed) } })
    }

    var paidBinding: Binding<Bool> {
        Binding(get: { store.isPaidConfirmationPresented }, set: { if !$0 { store.send(.paidDismissed) } })
    }

    var baseRefundBinding: Binding<Bool> {
        Binding(
            get: { store.isSendBaseBalanceConfirmationPresented },
            set: { if !$0 { store.send(.sendBaseBalanceToZecDismissed) } }
        )
    }

    var primaryTitle: String {
        switch store.page {
        case .loading: return String(localizable: .onrampRetry)
        case .unavailable: return String(localizable: .onrampRetry)
        case .amount: return String(localizable: .onrampGetQuote)
        case .confirmation: return String(localizable: .onrampPlaceOrder)
        case .progress:
            return store.isSettledAgainstUser
                ? String(localizable: .onrampStartOver)
                : String(localizable: .onrampCancelOrder)
        case .payment:
            // A lapsed local deadline says nothing about the order, so the way out is to ask the
            // service — not an irreversible start over that would drop the resume checkpoint.
            return store.isPayable
                ? String(localizable: .onrampIHavePaid)
                : String(localizable: .onrampCheckOrderStatus)
        case .convertingToZec: return String(localizable: .onrampConvertingAction)
        case .completion, .refundedToBase: return String(localizable: .onrampDone)
        case .deliveryNeedsAttention:
            if store.canRetryDelivery { return String(localizable: .onrampTryConversionAgain) }
            if store.delivery?.fundsLocation == .baseAccount || store.delivery?.fundsLocation == .recipientMismatch {
                return String(localizable: .onrampDone)
            }
            return String(localizable: .onrampCheckConversionStatus)
        }
    }

    var primaryEnabled: Bool {
        switch store.page {
        case .loading, .convertingToZec: return false
        case .amount, .confirmation: return store.canContinue
        case .payment: return store.isPayable || !store.isRecheckingOrder
        case .progress: return store.isSettledAgainstUser || store.progress?.phase == .awaitingMerchant
        default: return true
        }
    }

    func primaryTapped() {
        switch store.page {
        case .loading: break
        case .unavailable: store.send(.onAppear)
        case .amount, .confirmation: store.send(.continueTapped)
        case .progress: store.send(store.isSettledAgainstUser ? .retryTapped : .cancelTapped)
        case .payment: store.send(store.isPayable ? .paidTapped : .recheckOrderTapped)
        case .convertingToZec: break
        case .completion, .refundedToBase: store.send(.doneTapped)
        case .deliveryNeedsAttention:
            if store.canRetryDelivery { store.send(.deliveryActionTapped) }
            else if store.delivery?.fundsLocation == .baseAccount || store.delivery?.fundsLocation == .recipientMismatch {
                store.send(.doneTapped)
            } else {
                store.send(.deliveryActionTapped)
            }
        }
    }

    func duration(_ seconds: Int) -> String {
        String(format: "%d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
    }

    static func percent(_ basisPoints: Int) -> String {
        let value = Decimal(basisPoints) / 100
        return NSDecimalNumber(decimal: value).stringValue
    }
}
