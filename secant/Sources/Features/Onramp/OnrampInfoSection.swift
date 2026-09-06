//
//  OnrampInfoSection.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI

/// The header's info sheet and the two confirmation sheets, mirroring Android's
/// `OnrampInfoSection.kt`. The account detail lives here rather than on the page.
extension OnrampView {
    var infoSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localizable: .onrampInfoTitle)).zappFont(.sectionTitle, style: ZappColors.text)

            ForEach(Array(infoSteps.enumerated()), id: \.offset) { index, step in
                infoStep(index + 1, step)
            }

            if store.destination == .zcash {
                Text(String(localizable: .onrampInfoZcashCost)).zappFont(.caption, style: ZappColors.textMuted)
            }

            Text(store.destination == .zcash
                 ? String(localizable: .onrampInfoZcashNote)
                 : String(localizable: .onrampInfoNote))
                .zappFont(.caption, style: ZappColors.textMuted)

            if let address = store.accountAddress {
                infoAccountBlock(address)
            }

            ZappButton(title: String(localizable: .generalDone)) { store.send(.infoDismissed) }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 24)
    }

    /// Three steps either way, as Android lists them — the Zcash path swaps the merchant
    /// confirmation for the conversion rather than stacking a fourth.
    var infoSteps: [String] {
        store.destination == .zcash
            ? [
                String(localizable: .onrampInfoStepPay),
                String(localizable: .onrampInfoZcashStepSettle),
                String(localizable: .onrampInfoZcashStepConvert)
            ]
            : [
                String(localizable: .onrampInfoStepPay),
                String(localizable: .onrampInfoStepConfirm),
                String(localizable: .onrampInfoStepSettle)
            ]
    }

    func infoStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: "\(number)")
                .zappFont(.caption, style: ZappColors.accentText)
                .frame(width: 20, height: 20)
                .background(ZappColors.accentSoft.color(colorScheme))
            Text(text)
                .zappFont(.body, style: ZappColors.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The account reads as reference material, so it sits here rather than on the page — the
    /// same filing Android uses (`OnrampDestinationInfo`, "shown inside the existing sheet").
    func infoAccountBlock(_ address: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text((store.destination == .zcash
                  ? String(localizable: .onrampRefundAccountLabel)
                  : String(localizable: .onrampAccountLabel)).uppercased())
                .zappFont(.caption, style: ZappColors.textMuted)
            HStack(spacing: 10) {
                ZappExplorerLink(address: address, url: store.accountExplorerURL)
                Spacer(minLength: 8)
                Button { store.send(.copyAccountAddressTapped) } label: {
                    Asset.Assets.copy.image
                        .zImage(width: 20, height: 20, style: ZappColors.textMuted)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.zappPress)
                .accessibilityLabel(String(localizable: .onrampCopyAddress))
            }
        }
    }

    var paidConfirmationSheet: some View {
        confirmationSheet(
            title: String(localizable: .onrampPaidConfirmTitle),
            body: String(localizable: .onrampPaidConfirmBody),
            actionTitle: String(localizable: .onrampPaidConfirmAction),
            cancelTitle: String(localizable: .onrampPaidConfirmCancel),
            action: { store.send(.paidConfirmed) },
            cancel: { store.send(.paidDismissed) }
        )
    }

    var baseRefundSheet: some View {
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
    var baseRefundPreviewMessage: String? {
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

    func confirmationSheet(
        title: String,
        body: String,
        detail: String? = nil,
        actionTitle: String,
        cancelTitle: String,
        action: @escaping () -> Void,
        cancel: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).zappFont(.sectionTitle, style: ZappColors.text)
            Text(body).zappFont(.body, style: ZappColors.textMuted)
            if let detail {
                Text(detail).zappFont(.body, style: ZappColors.text)
            }
            ZappButton(title: actionTitle, action: action)
            ZappButton(title: cancelTitle, variant: .ghost, action: cancel)
        }
        .padding(.horizontal, 24)
        // The drag indicator is an overlay on iOS, not a laid-out handle as on Android, so the
        // sheet's first line sits under it unless the content insets itself.
        .padding(.top, 24)
        .padding(.bottom, 24)
    }
}
