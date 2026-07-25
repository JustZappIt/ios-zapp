//
//  ChatPaymentRequestBubble.swift
//  Zapp
//
//  Android's `view/bubbles/PaymentRequestBubble.kt`. Layout, headline logic, amount/fiat
//  precedence and the paid/payable states are all mirrored from it; the payload it reads is
//  documented in `ChatMessagePayloads.swift`.
//

import SwiftUI
import ZappMessaging

struct ChatPaymentRequestBubble: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let minWidth: CGFloat = 232
        static let maxWidth: CGFloat = 264
        static let headerIcon: CGFloat = 18
        static let paidIcon: CGFloat = 16
        static let headerHorizontal: CGFloat = 10
        static let headerVertical: CGFloat = 8
        static let bodyHorizontal: CGFloat = 12
        static let bodyVertical: CGFloat = 10
        static let footerHorizontal: CGFloat = 10
        static let footerVertical: CGFloat = 6
        static let chipHorizontal: CGFloat = 8
        static let chipVertical: CGFloat = 4
        static let memoPadding: CGFloat = 8
    }

    let message: ZMMessage
    /// Resolved by the store (local alias > wire name).
    var senderName: String?
    /// Our own messaging key — decides whether a request naming a debtor is ours to pay.
    var localPublicKey: String?
    var fiatRate: ChatFiatRate?
    /// True once a `zec-transaction` receipt in this room quotes this request's id.
    var isPaid = false
    var onPay: (() -> Void)?

    private var isFromMe: Bool { message.isFromMe }

    private var request: ChatPaymentRequest {
        ChatPaymentRequest.parse(message.content)
    }

    /// The recipient owes when the request targets them, or targets no one in a 1:1.
    private var isMineToPay: Bool {
        guard !isFromMe else { return false }
        guard let debtorId = request.debtorId else { return true }

        return PublicKeyRules.sanitize(debtorId) == localPublicKey.map(PublicKeyRules.sanitize)
    }

    private var isPayable: Bool {
        isMineToPay && !isPaid && request.isAmountValid && onPay != nil
    }

    var body: some View {
        VStack(alignment: isFromMe ? .trailing : .leading, spacing: Design.Spacing._xxs) {
            if !isFromMe, let senderName {
                Text(senderName)
                    .zappFont(.chip, style: ZappColors.accent)
                    .padding(.leading, Design.Spacing._xs)
            }

            card
        }
        .frame(maxWidth: .infinity, alignment: isFromMe ? .trailing : .leading)
    }

    private var card: some View {
        VStack(spacing: 0) {
            header
            details
            footer
        }
        .frame(minWidth: Constants.minWidth, maxWidth: Constants.maxWidth)
        .background(ZappColors.surface.color(colorScheme))
        .overlay {
            Rectangle()
                .strokeBorder(ZappColors.borderStrong.color(colorScheme), lineWidth: 1)
        }
        // Tapping anywhere on an owed, unpaid request opens the prefilled send — and the whole
        // card reads as one button to VoiceOver, rather than announcing a bare "Pay".
        .contentShape(Rectangle())
        .onTapGesture { if isPayable { onPay?() } }
        .accessibilityElement(children: isPayable ? .combine : .contain)
        .accessibilityAddTraits(isPayable ? .isButton : [])
    }

    private var header: some View {
        HStack(spacing: Design.Spacing._md) {
            Asset.Assets.Icons.currencyDollar.image
                .zImage(width: Constants.headerIcon, height: Constants.headerIcon, style: ZappColors.accentText)

            Text(headline.uppercased())
                .zappFont(.eyebrow, style: ZappColors.accentText)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Constants.headerHorizontal)
        .padding(.vertical, Constants.headerVertical)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ZappColors.accentSoft.color(colorScheme))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(labels.amount)
                .zappFont(.screenTitle, style: ZappColors.text)

            if let equivalent = labels.zecEquivalent {
                Text(equivalent)
                    .zappFont(.body, style: ZappColors.textMuted)
                    .padding(.top, Design.Spacing._xxs)
            }

            if request.isSplit {
                Text(String(localizable: .chatBubblePaymentRequestSplit(String(request.splitCount))))
                    .zappFont(.chip, style: ZappColors.accentText)
                    .padding(.horizontal, Constants.chipHorizontal)
                    .padding(.vertical, Constants.chipVertical)
                    .background(ZappColors.accentSoft.color(colorScheme))
                    .padding(.top, Design.Spacing._sm)
            }

            if let memo = request.memo {
                Text(memo)
                    .zappFont(.body, style: ZappColors.textMuted)
                    .padding(Constants.memoPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ZappColors.surfaceAlt.color(colorScheme))
                    .padding(.top, Design.Spacing._md)
            }
        }
        .padding(.horizontal, Constants.bodyHorizontal)
        .padding(.vertical, Constants.bodyVertical)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(ChatBubbleTime.label(for: message.timestamp))
                .zappFont(.caption, style: ZappColors.textSubtle)
                .frame(maxWidth: .infinity, alignment: .trailing)

            action
        }
        .padding(.horizontal, Constants.footerHorizontal)
        .padding(.vertical, Constants.footerVertical)
    }

    @ViewBuilder
    private var action: some View {
        if isPaid {
            HStack(spacing: Design.Spacing._sm) {
                Asset.Assets.Icons.checkVerifiedFilled.image
                    .zImage(width: Constants.paidIcon, height: Constants.paidIcon, style: ZappColors.success)

                Text(String(localizable: .chatBubblePaymentRequestPaid))
                    .zappFont(.chip, style: ZappColors.success)
            }
            .padding(.top, Design.Spacing._md)
        } else if isPayable {
            ZappButton(title: String(localizable: .chatBubblePaymentRequestPay)) {
                onPay?()
            }
            .padding(.top, Design.Spacing._lg)
        }
    }

    private var headline: String {
        if isFromMe {
            return String(localizable: .chatBubblePaymentRequestSent)
        }

        if isMineToPay {
            return String(localizable: .chatBubblePaymentRequestOwe)
        }

        return String(
            localizable: .chatBubblePaymentRequestOwes(
                request.debtorName ?? String(localizable: .generalUnknown)
            )
        )
    }

    /// The amount/equivalent pair, mirroring `parsePaymentRequest`'s precedence:
    /// an embedded fiat amount leads and pushes ZEC into the equivalent line; otherwise a live
    /// conversion leads; with no rate at all only ZEC is shown. Note that Android suppresses the
    /// EMBEDDED label too when there is no live rate — a stale price is not shown as a price.
    private var labels: (amount: String, zecEquivalent: String?) {
        let request = self.request
        let zecLabel = "\(ChatAmountFormat.zec(request.amount)) \(request.token)"

        guard let fiatRate else { return (zecLabel, nil) }

        if let embedded = embeddedFiatLabel(request) {
            return (embedded, "≈ \(zecLabel)")
        }

        guard request.amount > 0 else { return (zecLabel, nil) }

        let converted = ChatAmountFormat.fiat(
            ChatAmountFormat.roundedFiat(fiatRate.zecToFiat(request.amount))
        )

        return ("≈ \(fiatRate.symbol)\(converted)", zecLabel)
    }

    private func embeddedFiatLabel(_ request: ChatPaymentRequest) -> String? {
        guard
            let code = request.fiatCurrency,
            let currency = CurrencyISO4217(rawValue: code.uppercased()),
            let amount = request.fiatAmount,
            amount > 0
        else {
            return nil
        }

        return "\(currency.symbol)\(ChatAmountFormat.fiat(ChatAmountFormat.roundedFiat(amount)))"
    }
}

#Preview {
    let requestJSON = ChatPaymentRequest.json(
        id: "req-1",
        amount: Decimal(string: "0.125") ?? 0,
        requesterAddress: "utest1abc",
        memo: "Dinner at the sharp-cornered place",
        debtorName: "satoshi",
        splitCount: 3
    ) ?? ""

    return VStack(spacing: 8) {
        ChatPaymentRequestBubble(
            message: ZMMessage(
                id: "1",
                conversationId: "c",
                senderId: "peer",
                content: requestJSON,
                contentType: ChatContentType.paymentRequest,
                isFromMe: false
            ),
            senderName: "satoshi",
            onPay: { }
        )

        ChatPaymentRequestBubble(
            message: ZMMessage(
                id: "2",
                conversationId: "c",
                senderId: "me",
                content: requestJSON,
                contentType: ChatContentType.paymentRequest,
                isFromMe: true
            ),
            isPaid: true
        )
    }
    .padding(16)
    .applyScreenBackground()
}
