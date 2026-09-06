//
//  OnrampProgressSection.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI

/// Everything after the order is placed, mirroring Android's `OnrampProgressSection.kt`.
extension OnrampView {
    var progress: some View {
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

    var payment: some View {
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

    var converting: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localizable: .onrampConvertingAction))
                .zappFont(.screenTitle, style: ZappColors.text)
            Text(String(localizable: .onrampConvertingSubtitle))
                .zappFont(.body, style: ZappColors.textMuted)
            ProgressView().tint(ZappColors.accent.color(colorScheme))
            ZappOfframpStepList(items: progressItems)
        }
    }

    var completion: some View {
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

    var deliveryNeedsAttention: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localizable: .onrampConversionAttentionTitle))
                .zappFont(.screenTitle, style: ZappColors.text)
            dangerNotice(store.errorMessage ?? String(localizable: .onrampConversionStatusUncertain))
            if let address = store.accountAddress { accountCard(address) }
            ZappOfframpStepList(items: progressItems)
        }
    }

    func accountCard(_ address: String) -> some View {
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

    var progressItems: [ZappOfframpStepItem] {
        OnrampProgressMapper.map(
            status: store.progress,
            delivery: store.delivery,
            destination: store.destination
        ).map {
            ZappOfframpStepItem(id: $0.step.rawValue, label: stepTitle($0.step), detail: nil, status: $0.status)
        }
    }

    func stepTitle(_ step: OnrampVisibleStep) -> String {
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

    var progressSubtitle: String {
        if store.isSettledAgainstUser { return String(localizable: .onrampProgressSubtitleSettled) }
        if store.progress?.phase == .awaitingMerchant { return String(localizable: .onrampProgressSubtitleMatching) }
        return String(localizable: .onrampProgressSubtitleWorking)
    }

    var completionTitle: String {
        if store.page == .refundedToBase { return String(localizable: .onrampRefundedTitle) }
        return store.destination == .zcash
            ? String(localizable: .onrampZecCompletionTitle)
            : String(localizable: .onrampCompletionTitle)
    }

    var completionSubtitle: String {
        if store.page == .refundedToBase { return String(localizable: .onrampRefundedSubtitle) }
        return store.destination == .zcash
            ? String(localizable: .onrampZecCompletionSubtitle)
            : String(localizable: .onrampCompletionSubtitle)
    }

    var receivedText: String {
        if store.page == .refundedToBase { return store.receivedUsdc.map { "\($0) USDC" } ?? "—" }
        if store.destination == .zcash { return store.receivedZec.map { "\($0) ZEC" } ?? "—" }
        return store.receivedUsdc.map { "\($0) USDC" } ?? "—"
    }
}
