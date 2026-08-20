// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import SwiftUI

struct OnrampView: View {
    @Environment(\.colorScheme) private var colorScheme
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

                bottomBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .zappSwipeBack { store.send(.backTapped) }
            .onAppear { store.send(.onAppear) }
            .zashiSheet(isPresented: infoBinding) { infoSheet }
            .zashiSheet(isPresented: paidBinding) { paidConfirmationSheet }
            .zashiSheet(isPresented: baseRefundBinding) { baseRefundSheet }
        }
    }

    @ViewBuilder
    private var pageContent: some View {
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

    private var loading: some View {
        VStack(spacing: 14) {
            ProgressView().tint(ZappColors.accent.color(colorScheme))
            Text(String(localizable: .onrampProgressSubtitleWorking))
                .zappFont(.body, style: ZappColors.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localizable: .onrampUnavailableTitle))
                .zappFont(.screenTitle, style: ZappColors.text)
            Text(store.errorMessage ?? String(localizable: .onrampUnavailableBody))
                .zappFont(.body, style: ZappColors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var amount: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localizable: .onrampEyebrow).uppercased())
                .zappFont(.caption, style: ZappColors.accent)
            Text(String(localizable: .onrampHeadline))
                .zappFont(.screenTitle, style: ZappColors.text)
            Text(store.destination == .zcash
                 ? String(localizable: .onrampZcashSubtitle)
                 : String(localizable: .onrampSubtitle))
                .zappFont(.body, style: ZappColors.textMuted)

            if store.isZecDestinationEnabled {
                VStack(alignment: .leading, spacing: 7) {
                    Text(String(localizable: .onrampDestinationLabel))
                        .zappFont(.caption, style: ZappColors.textMuted)
                    ZappSegmentedSelector(
                        options: [
                            String(localizable: .onrampDestinationZcash),
                            String(localizable: .onrampDestinationBase)
                        ],
                        selectedIndex: store.destination == .zcash ? 0 : 1
                    ) { index in
                        store.send(.destinationSelected(index == 0 ? .zcash : .base))
                    }
                }
            }

            ZappAmountHero(
                label: String(localizable: .onrampAmountLabel),
                symbol: store.currencySymbol,
                amount: store.amount,
                balance: limitsText,
                isEnabled: !store.isRequestingQuote,
                onChange: { value in
                    MainActor.assumeIsolated {
                        _ = store.send(.amountChanged(value))
                    }
                }
            )

            ZappBorderedCard {
                VStack(spacing: 10) {
                    ZappSummaryRow(label: String(localizable: .onrampPaymentRailLabel), value: store.paymentRail)
                    ZappSummaryRow(label: String(localizable: .onrampDailyLimitLabel), value: dailyLimitText)
                }
            }

            if let address = store.accountAddress {
                accountCard(address)
            }

            baseBalanceCard
            errorText

            Text(String(localizable: .onrampQuoteDisclaimer))
                .zappFont(.caption, style: ZappColors.textMuted)
        }
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localizable: .onrampConfirmTitle))
                .zappFont(.screenTitle, style: ZappColors.text)

            if let quote = store.quote {
                ZappCompactLedger(rows: [
                    .init(
                        label: String(localizable: .onrampYouPayLabel),
                        value: "\(store.currencySymbol)\(Onramp.displayMicros(quote.fiatMicros))"
                    ),
                    .init(
                        label: String(localizable: .onrampYouReceiveLabel),
                        value: receiveQuoteText(quote)
                    ),
                    .init(
                        label: String(localizable: .onrampFeeLabel),
                        value: "\(Onramp.displayMicros(quote.feeUsdcMicros)) USDC"
                    ),
                    .init(
                        label: String(localizable: .onrampRateLabel),
                        value: "\(store.currencySymbol)\(Onramp.displayMicros(quote.buyPriceMicros)) / USDC"
                    )
                ])
            }

            if store.destination == .zcash {
                ZappBorderedCard {
                    if store.isRequestingZecEstimate {
                        HStack(spacing: 10) {
                            ProgressView().tint(ZappColors.accent.color(colorScheme))
                            Text(String(localizable: .onrampZecEstimateLoading))
                                .zappFont(.body, style: ZappColors.textMuted)
                        }
                    } else if let estimate = store.zecEstimate {
                        VStack(spacing: 10) {
                            ZappSummaryRow(
                                label: String(localizable: .onrampReceiveZecAfterSettlement),
                                value: "\(estimate.outputZec) ZEC"
                            )
                            ZappSummaryRow(
                                label: String(localizable: .onrampEstimatedConversionCostLabel),
                                value: "\(Self.percent(estimate.costBasisPoints))%"
                            )
                        }
                    }
                }
            }

            if let seconds = store.quoteSecondsRemaining {
                ZappSummaryRow(
                    label: String(localizable: .onrampQuoteExpiresInLabel),
                    value: duration(seconds)
                )
            }
            Text(String(localizable: .onrampQuoteRefreshNotice))
                .zappFont(.caption, style: ZappColors.textMuted)
            errorText
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localizable: .onrampProgressTitle))
                .zappFont(.screenTitle, style: ZappColors.text)
            Text(progressSubtitle)
                .zappFont(.body, style: ZappColors.textMuted)
            if let orderID = store.orderID {
                ZappSummaryRow(label: String(localizable: .onrampOrderIDLabel), value: orderID)
            }
            ZappOfframpStepList(items: progressItems)
            if let error = store.errorMessage {
                ZappBorderedCard(variant: .danger) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.progress?.kind == .cancelled
                             ? String(localizable: .onrampCancelledHeader)
                             : String(localizable: .onrampFailureHeader))
                            .zappFont(.rowTitle, style: ZappColors.danger)
                        Text(error).zappFont(.body, style: ZappColors.textMuted)
                    }
                }
            }
        }
    }

    private var payment: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localizable: .onrampPayMerchantTitle))
                .zappFont(.screenTitle, style: ZappColors.text)
            Text(String(localizable: .onrampPayMerchantBody))
                .zappFont(.body, style: ZappColors.textMuted)

            ZappBorderedCard {
                VStack(spacing: 10) {
                    if let fiat = store.progress?.fiatMicros {
                        ZappSummaryRow(
                            label: String(localizable: .onrampExactFiatAmount),
                            value: "\(store.currencySymbol)\(Onramp.displayMicros(fiat))"
                        )
                    }
                    if let address = store.paymentAddress {
                        ZappSummaryRow(label: String(localizable: .onrampPaymentAddressLabel), value: address)
                    }
                    if let seconds = store.paymentSecondsRemaining {
                        ZappSummaryRow(label: String(localizable: .onrampExpiresInLabel), value: duration(seconds))
                    }
                }
            }

            if let payload = store.qrPayload {
                OnrampQRCode(payload: payload)
                    .frame(maxWidth: 260, maxHeight: 260)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(String(localizable: .onrampQrContentDescription))
                Text(String(localizable: .onrampPayManuallyHint))
                    .zappFont(.caption, style: ZappColors.textMuted)
            }

            ZappButton(
                title: String(localizable: .onrampCopyPaymentDetails),
                variant: store.qrPayload == nil ? .primary : .ghost,
                leadingIcon: Asset.Assets.copy.image
            ) { store.send(.copyPaymentAddressTapped) }

            if store.isPaymentWindowClosed {
                dangerNotice(String(localizable: .onrampPaymentWindowClosed))
            } else if store.isPaymentAmountUntrusted {
                dangerNotice(String(localizable: .onrampErrorAmountMismatch))
            } else {
                Text(String(localizable: .onrampPaidWarning))
                    .zappFont(.caption, style: ZappColors.textMuted)
            }
            errorText
        }
    }

    private var converting: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localizable: .onrampConvertingAction))
                .zappFont(.screenTitle, style: ZappColors.text)
            Text(String(localizable: .onrampConvertingSubtitle))
                .zappFont(.body, style: ZappColors.textMuted)
            ProgressView().tint(ZappColors.accent.color(colorScheme))
            ZappOfframpStepList(items: progressItems)
        }
    }

    private var completion: some View {
        VStack(alignment: .leading, spacing: 18) {
            ZappSuccessHeader(title: completionTitle, subtitle: completionSubtitle)
            ZappBorderedCard {
                VStack(spacing: 10) {
                    ZappSummaryRow(label: String(localizable: .onrampReceivedLabel), value: receivedText)
                    if let fiat = store.fiatPaid {
                        ZappSummaryRow(
                            label: String(localizable: .onrampFiatPaidLabel),
                            value: "\(store.currencySymbol)\(fiat)"
                        )
                    }
                }
            }
            if store.page == .refundedToBase {
                Text(String(localizable: .onrampRefundedNotice))
                    .zappFont(.body, style: ZappColors.textMuted)
            }
            if let url = store.transactionExplorerURL {
                Link(String(localizable: .onrampViewTransaction), destination: url)
                    .zappFont(.button, style: ZappColors.accent)
            }
        }
    }

    private var deliveryNeedsAttention: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localizable: .onrampConversionAttentionTitle))
                .zappFont(.screenTitle, style: ZappColors.text)
            dangerNotice(store.errorMessage ?? String(localizable: .onrampConversionStatusUncertain))
            if let address = store.accountAddress { accountCard(address) }
            ZappOfframpStepList(items: progressItems)
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        ZappBottomActionBar(onBack: { store.send(.backTapped) }, isBackEnabled: !store.isSendingBaseBalanceToZec) {
            ZappButton(
                title: primaryTitle,
                variant: store.page == .progress && !store.isSettledAgainstUser ? .danger : .primary,
                isEnabled: primaryEnabled
            ) { primaryTapped() }
        }
    }

    private var baseBalanceCard: some View {
        Group {
            if let balance = store.baseBalance {
                ZappBorderedCard {
                    VStack(alignment: .leading, spacing: 10) {
                        ZappSummaryRow(label: String(localizable: .onrampBaseBalanceLabel), value: "\(balance) USDC")
                        if store.baseRefundState != .hidden {
                            ZappButton(
                                title: store.baseRefundState == .inProgress
                                    ? String(localizable: .onrampSendToZecInProgress)
                                    : String(localizable: .onrampSendToZec),
                                variant: .ghost,
                                isEnabled: store.baseRefundState == .available || store.baseRefundState == .failedRetry
                            ) { store.send(.sendBaseBalanceToZecTapped) }
                        }
                        if store.baseRefundState == .blocked {
                            Text(String(localizable: .offrampHistoryRefundBlocked))
                                .zappFont(.caption, style: ZappColors.textMuted)
                        }
                    }
                }
            }
        }
    }

    private func accountCard(_ address: String) -> some View {
        ZappBorderedCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(store.destination == .zcash
                     ? String(localizable: .onrampRefundAccountLabel)
                     : String(localizable: .onrampAccountLabel))
                    .zappFont(.caption, style: ZappColors.textMuted)
                HStack(spacing: 10) {
                    ZappExplorerLink(address: address, url: store.accountExplorerURL)
                    Spacer(minLength: 8)
                    Button { store.send(.copyAccountAddressTapped) } label: {
                        Asset.Assets.copy.image
                            .zImage(width: 20, height: 20, style: ZappColors.textMuted)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.zappPress)
                    .accessibilityLabel(String(localizable: .onrampCopyAddress))
                }
            }
        }
    }

    private var errorText: some View {
        Group {
            if let error = store.errorMessage {
                Text(error).zappFont(.caption, style: ZappColors.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func dangerNotice(_ message: String) -> some View {
        ZappBorderedCard(variant: .danger) {
            Text(message).zappFont(.body, style: ZappColors.danger)
        }
    }

    private var infoSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localizable: .onrampInfoTitle)).zappFont(.screenTitle, style: ZappColors.text)
            Text(String(localizable: .onrampInfoStepPay)).zappFont(.body, style: ZappColors.textMuted)
            Text(String(localizable: .onrampInfoStepConfirm)).zappFont(.body, style: ZappColors.textMuted)
            Text(store.destination == .zcash
                 ? String(localizable: .onrampInfoZcashStepSettle)
                 : String(localizable: .onrampInfoStepSettle))
                .zappFont(.body, style: ZappColors.textMuted)
            if store.destination == .zcash {
                Text(String(localizable: .onrampInfoZcashStepConvert)).zappFont(.body, style: ZappColors.textMuted)
                Text(String(localizable: .onrampInfoZcashCost)).zappFont(.caption, style: ZappColors.textMuted)
            }
            Text(store.destination == .zcash
                 ? String(localizable: .onrampInfoZcashNote)
                 : String(localizable: .onrampInfoNote))
                .zappFont(.caption, style: ZappColors.textMuted)
            ZappButton(title: String(localizable: .generalDone)) { store.send(.infoDismissed) }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var paidConfirmationSheet: some View {
        confirmationSheet(
            title: String(localizable: .onrampPaidConfirmTitle),
            body: String(localizable: .onrampPaidConfirmBody),
            actionTitle: String(localizable: .onrampPaidConfirmAction),
            cancelTitle: String(localizable: .onrampPaidConfirmCancel),
            action: { store.send(.paidConfirmed) },
            cancel: { store.send(.paidDismissed) }
        )
    }

    private var baseRefundSheet: some View {
        confirmationSheet(
            title: String(localizable: .onrampSendToZecConfirmTitle),
            body: String(localizable: .onrampSendToZecConfirmBody),
            detail: baseRefundPreviewMessage,
            actionTitle: String(localizable: .onrampSendToZecConfirmAction),
            cancelTitle: String(localizable: .onrampSendToZecCancel),
            action: { store.send(.sendBaseBalanceToZecConfirmed) },
            cancel: { store.send(.sendBaseBalanceToZecDismissed) }
        )
    }

    /// The exact quote the bridge holds authorized, so the sheet asks about the send that will run.
    private var baseRefundPreviewMessage: String? {
        guard let preview = store.baseRefundPreview else { return nil }
        var lines = [
            "\(preview.sourceAmount) \(preview.sourceAsset)",
            "\u{2192} \(preview.destinationAmount) \(preview.destinationAsset)"
        ]
        if let fee = preview.networkFee {
            lines.append("\(String(localizable: .offrampBridgePreviewFee)): \(fee) ZEC")
        }
        if preview.estimatedSeconds > 0 {
            lines.append("\(String(localizable: .offrampBridgePreviewTime)): \(preview.estimatedSeconds) s")
        }
        return lines.joined(separator: "\n")
    }

    private func confirmationSheet(
        title: String,
        body: String,
        detail: String? = nil,
        actionTitle: String,
        cancelTitle: String,
        action: @escaping () -> Void,
        cancel: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).zappFont(.screenTitle, style: ZappColors.text)
            Text(body).zappFont(.body, style: ZappColors.textMuted)
            if let detail {
                Text(detail).zappFont(.body, style: ZappColors.text)
            }
            ZappButton(title: actionTitle, action: action)
            ZappButton(title: cancelTitle, variant: .ghost, action: cancel)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var infoBinding: Binding<Bool> {
        Binding(get: { store.isInfoPresented }, set: { if !$0 { store.send(.infoDismissed) } })
    }

    private var paidBinding: Binding<Bool> {
        Binding(get: { store.isPaidConfirmationPresented }, set: { if !$0 { store.send(.paidDismissed) } })
    }

    private var baseRefundBinding: Binding<Bool> {
        Binding(
            get: { store.isSendBaseBalanceConfirmationPresented },
            set: { if !$0 { store.send(.sendBaseBalanceToZecDismissed) } }
        )
    }

    private var progressItems: [ZappOfframpStepItem] {
        OnrampProgressMapper.map(
            status: store.progress,
            delivery: store.delivery,
            destination: store.destination
        ).map {
            ZappOfframpStepItem(id: $0.step.rawValue, label: stepTitle($0.step), detail: nil, status: $0.status)
        }
    }

    private func stepTitle(_ step: OnrampVisibleStep) -> String {
        switch step {
        case .orderPlaced: return String(localizable: .onrampStepOrderPlaced)
        case .merchantMatched: return String(localizable: .onrampStepMerchantMatched)
        case .payMerchant: return String(localizable: .onrampStepPayMerchant)
        case .paymentConfirmed: return String(localizable: .onrampStepPaymentConfirmed)
        case .receivingUsdc: return String(localizable: .onrampStepReceiving)
        case .usdcReceived: return String(localizable: .onrampStepReceived)
        case .convertingToZec: return String(localizable: .onrampStepConvertingToZec)
        case .zecReceived: return String(localizable: .onrampStepZecReceived)
        }
    }

    private var primaryTitle: String {
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

    private var primaryEnabled: Bool {
        switch store.page {
        case .loading, .convertingToZec: return false
        case .amount, .confirmation: return store.canContinue
        case .payment: return store.isPayable || !store.isRecheckingOrder
        case .progress: return store.isSettledAgainstUser || store.progress?.phase == .awaitingMerchant
        default: return true
        }
    }

    private func primaryTapped() {
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

    private var limitsText: String? {
        guard let limits = store.limits else { return nil }
        let minimum = Onramp.displayMicros(limits.minimumFiatMicros)
        let maximum = Onramp.displayMicros(limits.maximumFiatMicros)
        return "\(store.currencySymbol)\(minimum)–\(store.currencySymbol)\(maximum)"
    }

    private var dailyLimitText: String {
        guard let value = store.limits?.dailyFiatMicros else { return String(localizable: .onrampBaseBalanceUnavailable) }
        return "\(store.currencySymbol)\(Onramp.displayMicros(value))"
    }

    private func receiveQuoteText(_ quote: OnrampQuoteModel) -> String {
        if store.destination == .zcash {
            return store.zecEstimate.map { "\($0.outputZec) ZEC" } ?? String(localizable: .onrampZecEstimateLoading)
        }
        return "\(Onramp.displayMicros(quote.netUsdcMicros)) USDC"
    }

    private var progressSubtitle: String {
        if store.isSettledAgainstUser { return String(localizable: .onrampProgressSubtitleSettled) }
        if store.progress?.phase == .awaitingMerchant { return String(localizable: .onrampProgressSubtitleMatching) }
        return String(localizable: .onrampProgressSubtitleWorking)
    }

    private var completionTitle: String {
        if store.page == .refundedToBase { return String(localizable: .onrampRefundedTitle) }
        return store.destination == .zcash
            ? String(localizable: .onrampZecCompletionTitle)
            : String(localizable: .onrampCompletionTitle)
    }

    private var completionSubtitle: String {
        if store.page == .refundedToBase { return String(localizable: .onrampRefundedSubtitle) }
        return store.destination == .zcash
            ? String(localizable: .onrampZecCompletionSubtitle)
            : String(localizable: .onrampCompletionSubtitle)
    }

    private var receivedText: String {
        if store.page == .refundedToBase { return store.receivedUsdc.map { "\($0) USDC" } ?? "—" }
        if store.destination == .zcash { return store.receivedZec.map { "\($0) ZEC" } ?? "—" }
        return store.receivedUsdc.map { "\($0) USDC" } ?? "—"
    }

    private func duration(_ seconds: Int) -> String {
        String(format: "%d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
    }

    private static func percent(_ basisPoints: Int) -> String {
        let value = Decimal(basisPoints) / 100
        return NSDecimalNumber(decimal: value).stringValue
    }
}
