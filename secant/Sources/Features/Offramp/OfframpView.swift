// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import SwiftUI

struct OfframpView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Perception.Bindable var store: StoreOf<Offramp>
    @State private var isPaymentInfoPresented = false

    var body: some View {
        WithPerceptionTracking {
            Group {
                switch store.page {
                case .corridors: corridors
                case .scanner: scanner
                case .amount: amount
                case .topUp: topUp
                case .progress: progress
                case .history: history
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .onAppear { store.send(.onAppear) }
            .zashiSheet(isPresented: $isPaymentInfoPresented) { paymentMethodInfo }
            .alert(
                text("offramp.refund.confirm.title", "Return Base funds to ZEC?"),
                isPresented: Binding(
                    get: { store.isRefundConfirmationPresented },
                    set: { if !$0 { store.send(.refundDismissed) } }
                )
            ) {
                Button(text("general.cancel", "Cancel"), role: .cancel) { store.send(.refundDismissed) }
                Button(text("offramp.refund.confirm.button", "Return funds")) { store.send(.refundConfirmed) }
            } message: {
                Text(text(
                    "offramp.refund.confirm.message",
                    "Your full Base USDC balance will be bridged back to this wallet as ZEC."
                ))
            }
        }
    }

    private var corridors: some View {
        VStack(spacing: 0) {
            ZappScreenHeader(title: text("offramp.paymentMethod", "P2P payment method")) {
                Button { isPaymentInfoPresented = true } label: {
                    Asset.Assets.infoCircle.image
                        .zImage(width: 20, height: 20, style: ZappColors.text)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.zappPress)
                .accessibilityLabel(text("offramp.paymentMethod.infoButton", "How P2P payments work"))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach(store.corridors) { corridor in
                            corridorRow(corridor)
                            if corridor.id != store.corridors.last?.id { ZappRowDivider(inset: false) }
                        }
                    }
                    .background(ZappColors.surface.color(colorScheme))
                    .overlay(Rectangle().stroke(ZappColors.border.color(colorScheme), lineWidth: 1))
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 110)
            }
            ZappBottomActionBar(onBack: { store.send(.backTapped) }) {
                ZappButton(title: text("general.save", "Save")) { store.send(.saveCorridorTapped) }
            }
        }
    }

    private var scanner: some View {
        OfframpScanner(
            title: store.selectedCorridor.map {
                String(format: text("offramp.scan.title", "Scan %@ QR"), $0.paymentRail)
            } ?? text("offramp.scan.titleFallback", "Scan payment QR"),
            errorMessage: store.errorMessage,
            isLoading: store.isLoading,
            checkpointMessage: store.hasCheckpoint && !store.isResumingCheckpoint
                ? text(
                    "offramp.checkpoint.message",
                    "A P2P payment is still in progress. Resume it before starting another payment, or discard it."
                )
                : nil,
            onCode: { store.send(.scanPayload($0)) },
            onPhotoFailure: {
                store.send(.scanFailed(text("offramp.scan.photoError", "No QR code was found in that photo.")))
            },
            onResumeCheckpoint: { store.send(.resumeCheckpointTapped) },
            onDiscardCheckpoint: { store.send(.discardCheckpointTapped) },
            onBack: { store.send(.backTapped) }
        )
    }

    private var amount: some View {
        VStack(spacing: 0) {
            ZappScreenHeader(title: text("offramp.pay.title", "Pay a merchant"))
            ScrollView {
                VStack(spacing: 18) {
                    if let corridor = store.selectedCorridor {
                        Button { store.send(.chooseCorridorTapped) } label: {
                            HStack(spacing: 14) {
                                Text(corridor.flag).font(.system(size: 30))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(corridor.countryName).zappFont(.rowTitle, style: ZappColors.text)
                                    Text("\(corridor.paymentRail) · \(corridor.currencyCode)")
                                        .zappFont(.caption, style: ZappColors.textMuted)
                                }
                                Spacer()
                                Asset.Assets.chevronRight.image
                                    .zImage(width: 16, height: 16, style: ZappColors.textMuted)
                            }
                            .padding(16)
                            .background(ZappColors.surface.color(colorScheme))
                            .overlay(Rectangle().stroke(ZappColors.border.color(colorScheme), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }

                    if let account = store.account {
                        accountBalanceCard(account)
                    }

                    if store.hasCheckpoint && !store.isResumingCheckpoint {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(text("offramp.checkpoint.title", "Payment already in progress"))
                                .zappFont(.rowTitle, style: ZappColors.text)
                            Text(text(
                                "offramp.checkpoint.message",
                                "Resume the existing P2P payment before starting another, or discard it."
                            ))
                            .zappFont(.body, style: ZappColors.textMuted)
                            HStack(spacing: 10) {
                                ZappButton(
                                    title: text("offramp.checkpoint.discard", "Discard"),
                                    variant: .ghost
                                ) { store.send(.discardCheckpointTapped) }
                                ZappButton(title: text("offramp.checkpoint.resume", "Resume")) {
                                    store.send(.resumeCheckpointTapped)
                                }
                            }
                        }
                        .padding(16)
                        .background(ZappColors.surface.color(colorScheme))
                        .overlay(Rectangle().stroke(ZappColors.border.color(colorScheme), lineWidth: 1))
                    }

                    VStack(spacing: 6) {
                        TextField("0", text: Binding(
                            get: { store.fiatAmount },
                            set: { store.send(.fiatAmountChanged($0)) }
                        ))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .zappFont(.display, style: ZappColors.text)
                        Text(store.selectedCorridor?.currencyCode ?? store.selectedCurrencyCode)
                            .zappFont(.caption, style: ZappColors.textMuted)
                    }
                    .padding(.vertical, 20)

                    if let quote = store.quote {
                        quoteCard(quote)
                    }

                    if let error = store.errorMessage {
                        errorCard(error)
                    }

                    ZappButton(
                        title: text("offramp.addFunds.base", "Add funds to Base"),
                        variant: .ghost,
                        isEnabled: !store.isLoading
                    ) { store.send(.addFundsTapped) }

                    Button { store.send(.historyTapped) } label: {
                        HStack {
                            Text(text("offramp.history.recent", "Recent P2P payments"))
                                .zappFont(.rowTitle, style: ZappColors.text)
                            Spacer()
                            Asset.Assets.chevronRight.image
                                .zImage(width: 16, height: 16, style: ZappColors.textMuted)
                        }
                        .padding(16)
                        .overlay(Rectangle().stroke(ZappColors.border.color(colorScheme), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(18)
                .padding(.bottom, 110)
            }

            ZappBottomActionBar(onBack: { store.send(.backTapped) }) {
                if let quote = store.quote {
                    ZappButton(
                        title: quote.canPayFromBase
                            ? text("offramp.pay.button", "Pay")
                            : text("offramp.addFunds.button", "Add funds"),
                        isEnabled: !store.isLoading && !store.hasCheckpoint
                    ) {
                        store.send(quote.canPayFromBase ? .payTapped : .addFundsTapped)
                    }
                } else {
                    ZappButton(
                        title: store.isLoading
                            ? text("offramp.quote.loading", "Getting quote…")
                            : text("offramp.quote.button", "Review"),
                        isEnabled: !store.fiatAmount.isEmpty && !store.isLoading && !store.hasCheckpoint
                    ) { store.send(.quoteTapped) }
                }
            }
        }
    }

    private var topUp: some View {
        VStack(spacing: 0) {
            ZappScreenHeader(title: text("offramp.topup.title", "Add funds to Base"))
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 6) {
                        Text(text("offramp.topup.amount", "Amount to add"))
                            .zappFont(.eyebrow, style: ZappColors.textMuted)
                        TextField("0", text: Binding(
                            get: { store.topUpAmount },
                            set: { store.send(.topUpAmountChanged($0)) }
                        ))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .zappFont(.display, style: ZappColors.text)
                        Text("USDC").zappFont(.caption, style: ZappColors.textMuted)
                    }
                    .padding(20)
                    .background(ZappColors.surface.color(colorScheme))
                    .overlay(Rectangle().stroke(ZappColors.border.color(colorScheme), lineWidth: 1))

                    if let account = store.account {
                        accountBalanceCard(account)
                    }
                    if store.account?.canBridgeToBase == true {
                        progressStep(1, text("offramp.topup.step1", "Approve the ZEC bridge"), active: true)
                        progressStep(2, text("offramp.topup.step2", "Wait for USDC on Base"), active: false)
                        progressStep(3, text("offramp.topup.step3", "Return and pay from your Base balance"), active: false)
                    } else {
                        callout(
                            title: text("offramp.topup.testnet.title", "Fund your testnet Base account"),
                            detail: text(
                                "offramp.topup.testnet.detail",
                                "Automatic ZEC bridging is unavailable on testnet. Send testnet USDC to this Base account."
                            )
                        )
                        if let account = store.account { accountAddressCard(account) }
                    }
                }
                .padding(18)
            }
            ZappBottomActionBar(onBack: { store.send(.backTapped) }) {
                if store.account?.canBridgeToBase == true {
                    ZappButton(
                        title: text("offramp.topup.continue", "Add funds"),
                        isEnabled: Offramp.usdcMicros(store.topUpAmount) != nil && !store.isLoading
                    ) {
                        store.send(.startTopUpTapped)
                    }
                }
            }
        }
    }

    private var progress: some View {
        VStack(spacing: 0) {
            ZappScreenHeader(title: store.latestProgress?.title ?? text("offramp.progress", "Payment in progress"))
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if store.progress.isEmpty {
                        ProgressView().tint(ZappColors.accent.color(colorScheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    }
                    ForEach(Array(store.progress.enumerated()), id: \.offset) { index, status in
                        progressStep(index + 1, status.title, active: index == store.progress.count - 1)
                        if let detail = status.detail { Text(detail).zappFont(.caption, style: ZappColors.textMuted) }
                    }
                    if let latest = store.latestProgress, latest.isTerminal {
                        callout(
                            title: latest.isSuccess
                                ? text("offramp.progress.success", "Complete")
                                : text("offramp.progress.stopped", "Payment stopped"),
                            detail: latest.detail ?? latest.title
                        )
                    }
                }
                .padding(18)
                .padding(.bottom, 110)
            }
            ZappBottomActionBar(onBack: { store.send(.backTapped) }) {
                if store.latestProgress?.isTerminal == true {
                    ZappButton(title: text("general.done", "Done")) { store.send(.backTapped) }
                }
            }
        }
    }

    private var history: some View {
        VStack(spacing: 0) {
            ZappScreenHeader(title: text("offramp.history.title", "P2P transactions"))
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let account = store.account {
                        accountBalanceCard(account)
                            .padding(.bottom, 14)
                    }
                    if store.history.isEmpty && !store.isLoading {
                        callout(
                            title: text("offramp.history.empty", "No P2P payments yet"),
                            detail: text("offramp.history.emptyDetail", "Your completed and cancelled orders will appear here.")
                        )
                    }
                    ForEach(store.history) { item in
                        historyRow(item)
                        ZappRowDivider(inset: false)
                    }
                }
                .padding(18)
                .padding(.bottom, 90)
            }
            ZappBottomActionBar(onBack: { store.send(.backTapped) })
        }
    }

    private func corridorRow(_ corridor: OfframpCorridor) -> some View {
        Button { store.send(.draftCorridorTapped(corridor.currencyCode)) } label: {
            HStack(spacing: 14) {
                Text(corridor.flag).font(.system(size: 28))
                VStack(alignment: .leading, spacing: 3) {
                    Text(corridor.countryName).zappFont(.rowTitle, style: ZappColors.text)
                    Text("\(corridor.paymentRail) · \(corridor.currencyCode)")
                        .zappFont(.caption, style: ZappColors.textMuted)
                }
                Spacer()
                if corridor.currencyCode == store.draftCurrencyCode {
                    Asset.Assets.Icons.checkSolid.image.zImage(width: 20, height: 20, style: ZappColors.accent)
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func quoteCard(_ quote: OfframpQuoteModel) -> some View {
        VStack(spacing: 12) {
            infoRow(text("offramp.quote.youPay", "P2P order"), "\(quote.usdcDisplay) USDC")
            infoRow(text("offramp.quote.rate", "Rate"), "1 USDC = \(quote.sellRate) \(quote.currencyCode)")
            infoRow(text("offramp.quote.fee", "Fixed fee"), "\(quote.fixedFeeDisplay) USDC")
            infoRow(text("offramp.quote.balance", "Available on Base"), "\(quote.baseBalanceDisplay) USDC")
            if !quote.canPayFromBase {
                infoRow(text("offramp.quote.shortfall", "Add first"), "\(quote.shortfallDisplay) USDC")
            }
        }
        .padding(16)
        .overlay(Rectangle().stroke(ZappColors.border.color(colorScheme), lineWidth: 1))
    }

    private func historyRow(_ item: OfframpHistoryModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("#\(item.id)").zappFont(.rowTitle, style: ZappColors.text)
                Spacer()
                Text(item.status.capitalized).zappFont(.caption, style: ZappColors.accent)
            }
            if let address = item.paymentAddress {
                Text(address).zappFont(.caption, style: ZappColors.textMuted).lineLimit(1)
            }
            Text("\(formatMicros(item.fiatMicros)) \(item.currencyCode) · \(formatMicros(item.usdcMicros)) USDC")
                .zappFont(.body, style: ZappColors.text)
            if let fee = item.fixedFeeMicros {
                infoRow(text("offramp.history.fee", "Fee"), "\(formatMicros(fee)) USDC")
            }
            if let date = item.completedAt ?? item.cancelledAt ?? item.placedAt {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .zappFont(.caption, style: ZappColors.textSubtle)
            }
            if item.status == "CANCELLED" {
                ZappButton(title: text("offramp.history.recover", "Get funds back to ZEC"), variant: .ghost) {
                    store.send(.recoverTapped(item.id))
                }
            }
        }
        .padding(.vertical, 14)
    }

    private var paymentMethodInfo: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text("offramp.paymentMethod.infoTitle", "How P2P payments work"))
                .zappFont(.sectionTitle, style: ZappColors.text)
            Text(text(
                "offramp.paymentMethod.infoRails",
                "Choose the country whose payment QR you want to scan. Zapp validates the matching UPI, PIX, QRIS, Mercado Pago, Pago Móvil, NIP, or Colombian transfer format on your device."
            ))
            .zappFont(.body, style: ZappColors.textMuted)
            Text(text(
                "offramp.paymentMethod.infoFlow",
                "ZEC can be bridged to your self-custodial Base account, then exchanged through the P2P contract. Review the amount and rate before approving."
            ))
            .zappFont(.body, style: ZappColors.textMuted)
            if let account = store.account { accountAddressCard(account) }
            ZappButton(title: text("general.ok", "OK")) { isPaymentInfoPresented = false }
        }
        .padding(.bottom, Design.Spacing.sheetBottomSpace)
    }

    private func accountBalanceCard(_ account: OfframpAccountModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(text("offramp.history.balance", "BASE BALANCE"))
                        .zappFont(.eyebrow, style: ZappColors.textMuted)
                    Text(account.balanceDisplay.map { "\($0) USDC" } ?? "— USDC")
                        .zappFont(.display, style: ZappColors.text)
                }
                Spacer()
                if account.canRefundToZec {
                    Button { store.send(.refundTapped) } label: {
                        Text(text("offramp.history.refund", "Return to ZEC"))
                            .zappFont(.buttonSmall, style: ZappColors.onAccent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(ZappColors.accent.color(colorScheme))
                    }
                    .buttonStyle(.zappPress)
                }
            }
            accountAddressCard(account)
        }
        .padding(16)
        .background(ZappColors.surface.color(colorScheme))
        .overlay(Rectangle().stroke(ZappColors.border.color(colorScheme), lineWidth: 1))
    }

    private func accountAddressCard(_ account: OfframpAccountModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text("offramp.account.label", "Your Base account"))
                .zappFont(.caption, style: ZappColors.textMuted)
            HStack(spacing: 10) {
                if let url = account.explorerURL {
                    Link(account.address, destination: url)
                        .zappFont(.mono, style: ZappColors.text)
                        .lineLimit(2)
                } else {
                    Text(account.address)
                        .zappFont(.mono, style: ZappColors.text)
                        .lineLimit(2)
                }
                Spacer()
                Button { store.send(.copyAccountAddressTapped) } label: {
                    Asset.Assets.copy.image
                        .zImage(width: 20, height: 20, style: store.isAddressCopied ? ZappColors.success : ZappColors.textMuted)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.zappPress)
                .accessibilityLabel(text("offramp.account.copy", "Copy Base account"))
            }
        }
        .padding(14)
        .background(ZappColors.surfaceAlt.color(colorScheme))
        .overlay(Rectangle().stroke(ZappColors.border.color(colorScheme), lineWidth: 1))
    }

    private func callout(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(ZappColors.accent.color(colorScheme)).frame(width: 3, height: 20)
            Text(title).zappFont(.rowTitle, style: ZappColors.text)
            Text(detail).zappFont(.body, style: ZappColors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(ZappColors.surface.color(colorScheme))
    }

    private func errorCard(_ message: String) -> some View {
        Text(message)
            .zappFont(.body, style: ZappColors.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .overlay(Rectangle().stroke(ZappColors.danger.color(colorScheme), lineWidth: 1))
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).zappFont(.caption, style: ZappColors.textMuted)
            Spacer()
            Text(value).zappFont(.body, style: ZappColors.text).multilineTextAlignment(.trailing)
        }
    }

    private func progressStep(_ number: Int, _ title: String, active: Bool) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .zappFont(.caption, style: active ? ZappColors.onAccent : ZappColors.textMuted)
                .frame(width: 28, height: 28)
                .background(active ? ZappColors.accent.color(colorScheme) : ZappColors.surface.color(colorScheme))
            Text(title).zappFont(.rowTitle, style: active ? ZappColors.text : ZappColors.textMuted)
            Spacer()
        }
    }

    private func formatMicros(_ value: String) -> String {
        let decimal = Decimal(string: value) ?? 0
        return NSDecimalNumber(decimal: decimal / 1_000_000).stringValue
    }

    private func text(_ key: String, _ fallback: String) -> String {
        Bundle.main.localizedString(forKey: key, value: fallback, table: nil)
    }
}
