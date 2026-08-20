// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import SwiftUI

struct OfframpView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Perception.Bindable var store: StoreOf<Offramp>
    @State private var isPaymentInfoPresented = false
    @State private var isTopUpInfoPresented = false

    private let amountStyle = ZappTextStyle(weight: .semiBold, size: 32, lineHeight: 36, tracking: -1)

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
            .zappSwipeBack { store.send(.backTapped) }
            .onAppear { store.send(.onAppear) }
            .zashiSheet(isPresented: $isPaymentInfoPresented) { paymentMethodInfo }
            .zashiSheet(isPresented: $isTopUpInfoPresented) { topUpInfo }
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
                Text(bridgePreviewMessage)
            }
            .alert(
                text("offramp.pay.updated.title", "Review updated payment quote"),
                isPresented: Binding(
                    get: { store.isPayConfirmationPresented },
                    set: { if !$0 { store.send(.payDismissed) } }
                )
            ) {
                Button(text("general.cancel", "Cancel"), role: .cancel) { store.send(.payDismissed) }
                Button(text("offramp.pay.confirm", "Confirm payment")) { store.send(.payConfirmed) }
            } message: {
                Text(text(
                    "offramp.pay.updated.message",
                    "The rate, fee, or required USDC changed. Review the updated quote before confirming."
                ))
            }
            .alert(
                text("offramp.topup.confirm.title", "Confirm ZEC bridge"),
                isPresented: Binding(
                    get: { store.isTopUpConfirmationPresented },
                    set: { if !$0 { store.send(.topUpDismissed) } }
                )
            ) {
                Button(text("general.cancel", "Cancel"), role: .cancel) { store.send(.topUpDismissed) }
                Button(text("offramp.topup.confirm.button", "Bridge funds")) { store.send(.topUpConfirmed) }
            } message: {
                Text(bridgePreviewMessage)
            }
            .alert(
                text("offramp.topup.discard.confirm.title", "Discard saved top-up?"),
                isPresented: Binding(
                    get: { store.isTopUpDiscardConfirmationPresented },
                    set: { if !$0 { store.send(.discardTopUpCheckpointDismissed) } }
                )
            ) {
                Button(text("general.cancel", "Cancel"), role: .cancel) {
                    store.send(.discardTopUpCheckpointDismissed)
                }
                Button(text("offramp.topup.discard", "Discard saved top-up"), role: .destructive) {
                    store.send(.discardTopUpCheckpointConfirmed)
                }
            } message: {
                Text(text(
                    "offramp.topup.discard.confirm.message",
                    "Discard only after verifying the previous bridge cannot settle. Starting again may send ZEC twice."
                ))
            }
            .alert(
                text("offramp.checkpoint.discard.confirm.title", "Discard saved payment?"),
                isPresented: Binding(
                    get: { store.isCheckpointDiscardConfirmationPresented },
                    set: { if !$0 { store.send(.discardCheckpointDismissed) } }
                )
            ) {
                Button(text("general.cancel", "Cancel"), role: .cancel) {
                    store.send(.discardCheckpointDismissed)
                }
                Button(text("offramp.checkpoint.discard", "Discard"), role: .destructive) {
                    store.send(.discardCheckpointConfirmed)
                }
            } message: {
                Text(text(
                    "offramp.checkpoint.discard.confirm.message",
                    "Discarding hides local recovery for this order. Verify it is terminal before continuing."
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
                    .overlay(Rectangle().strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1))
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 110)
            }
            ZappBottomActionBar(onBack: { store.send(.backTapped) }) {
                ZappButton(
                    title: text("general.save", "Save"),
                    isEnabled: store.canSaveCorridor
                ) { store.send(.saveCorridorTapped) }
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
            onCameraFailure: {
                store.send(.scanFailed(text(
                    "offramp.scan.cameraError",
                    "Camera access is unavailable. Allow camera access in Settings or choose a photo."
                )))
            },
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
            ZappScreenHeader(title: text("offramp.pay.title", "Pay a merchant")) {
                infoButton { isPaymentInfoPresented = true }
            }
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        amountHero

                        settlementLedger
                            .padding(.top, 6)

                        if let error = store.errorMessage {
                            Text(error)
                                .zappFont(.caption, style: ZappColors.danger)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 10)
                        }

                        ZappButton(
                            title: text("offramp.addFunds.base", "Add funds to Base"),
                            variant: .ghost,
                            isEnabled: !store.isLoading
                        ) { store.send(.addFundsTapped) }
                        .padding(.top, 16)

                        if store.hasCheckpoint && !store.isResumingCheckpoint {
                            checkpointActions
                                .padding(.top, 12)
                        }

                        Spacer(minLength: 16)
                        recentTransactionsButton
                            .padding(.bottom, 12)
                    }
                    .frame(minHeight: geometry.size.height, alignment: .top)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                }
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
                            && Offramp.hasPositiveAmount(store.fiatAmount)
                    ) { store.send(.quoteTapped) }
                }
            }
        }
    }

    private var amountHero: some View {
        VStack(spacing: 6) {
            HStack {
                Text(text("offramp.pay.amount", "AMOUNT"))
                    .zappFont(.eyebrow, style: ZappColors.textMuted)
                Spacer()
                Text(store.selectedCorridor?.currencyCode ?? store.selectedCurrencyCode)
                    .zappFont(.caption, style: ZappColors.textMuted)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let corridor = store.selectedCorridor {
                    Text(corridor.flag)
                        .font(.system(size: 28))
                    Text(corridor.symbol)
                        .zappFont(amountStyle, style: ZappColors.text)
                }
                TextField("0", text: Binding(
                    get: { store.fiatAmount },
                    set: { store.send(.fiatAmountChanged($0)) }
                ))
                .keyboardType(.decimalPad)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.leading)
                .zappFont(amountStyle, style: ZappColors.text)
            }
            .padding(.vertical, 4)

            Rectangle()
                .fill(store.errorMessage == nil
                    ? ZappColors.accent.color(colorScheme)
                    : ZappColors.danger.color(colorScheme))
                .frame(height: 2)

            if let quote = store.quote {
                Text("≈ \(quote.usdcDisplay) USDC · \(text("offramp.pay.whatYouPay", "what you pay"))")
                    .zappFont(.body, style: ZappColors.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
        }
    }

    private var settlementLedger: some View {
        VStack(spacing: 6) {
            ZappCompactLedger(rows: [
                ZappCompactLedgerRow(
                    label: text("offramp.quote.rate", "Rate"),
                    value: store.quote.map { "1 USDC = \($0.sellRate) \($0.currencyCode)" } ?? "—"
                ),
                ZappCompactLedgerRow(
                    label: text("offramp.pay.baseBalance", "Base balance"),
                    value: store.account?.balanceDisplay.map { "\($0) USDC" } ?? "—"
                )
            ])

            if let quote = store.quote, !quote.canPayFromBase {
                Text(String(
                    format: text(
                        "offramp.pay.fundingPlan",
                        "You'll add about %@ USDC to Base first, then pay."
                    ),
                    quote.shortfallDisplay
                ))
                .zappFont(.caption, style: ZappColors.accentText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(ZappColors.accentSoft.color(colorScheme))
            }
        }
    }

    private var checkpointActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text(
                "offramp.checkpoint.message",
                "A P2P payment is still in progress. Resume it before starting another payment."
            ))
            .zappFont(.caption, style: ZappColors.danger)

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
    }

    private var recentTransactionsButton: some View {
        Button { store.send(.historyTapped) } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 18, weight: .semibold))
                Text(text("offramp.history.recent", "Recent transactions"))
                    .zappFont(.caption, style: ZappColors.accent)
            }
            .foregroundStyle(ZappColors.accent.color(colorScheme))
            .padding(.horizontal, 8)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.zappPress)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 4)
    }

    private var topUp: some View {
        VStack(spacing: 0) {
            ZappScreenHeader(title: text("offramp.topup.title", "Add funds to Base")) {
                infoButton { isTopUpInfoPresented = true }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(text("offramp.topup.amount", "Amount to add"))
                            .zappFont(.eyebrow, style: ZappColors.textMuted)
                        HStack(spacing: 8) {
                            Text(topUpUsesFiat
                                ? store.selectedCorridor?.symbol ?? ""
                                : "USDC")
                                .zappFont(amountStyle, style: ZappColors.text)
                            TextField("0", text: topUpAmountBinding)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.leading)
                                .zappFont(amountStyle, style: ZappColors.text)
                        }
                        .padding(.vertical, 4)

                        Rectangle()
                            .fill(store.isTopUpAmountInsufficient
                                ? ZappColors.danger.color(colorScheme)
                                : ZappColors.accent.color(colorScheme))
                            .frame(height: 2)

                        if topUpUsesFiat, !store.topUpAmount.isEmpty {
                            Text("≈ \(store.topUpAmount) USDC · \(text("offramp.topup.landsOnBase", "lands on Base"))")
                                .zappFont(.body, style: ZappColors.textMuted)
                        }
                    }

                    if let account = store.account {
                        Text(String(
                            format: text("offramp.topup.baseBalance", "Base balance: %@"),
                            account.balanceDisplay.map { "\($0) USDC" } ?? "—"
                        ))
                        .zappFont(.caption, style: ZappColors.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let validation = topUpValidationMessage ?? store.errorMessage {
                        Text(validation)
                            .zappFont(.caption, style: ZappColors.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if store.account?.canBridgeToBase == true {
                        if store.hasTopUpCheckpoint {
                            callout(
                                title: text("offramp.topup.resume.title", "Base top-up in progress"),
                                detail: text(
                                    "offramp.topup.resume.detail",
                                    "Resume the saved bridge to avoid sending ZEC twice, or discard it only if you have verified it will not settle."
                                )
                            )
                            ZappButton(
                                title: text("offramp.topup.discard", "Discard saved top-up"),
                                variant: .danger
                            ) { store.send(.discardTopUpCheckpointTapped) }
                        }
                    } else {
                        callout(
                            title: text("offramp.topup.testnet.title", "Fund your testnet Base account"),
                            detail: text(
                                "offramp.topup.testnet.detail",
                                "Automatic ZEC bridging is unavailable on testnet. Send testnet USDC to this Base account."
                            )
                        )
                    }
                }
                .padding(18)
            }
            ZappBottomActionBar(onBack: { store.send(.backTapped) }) {
                if store.account?.canBridgeToBase == true {
                    ZappButton(
                        title: store.isTopUpValidationLoading
                            ? text("offramp.topup.checking.android", "Checking balance…")
                            : store.hasTopUpCheckpoint
                            ? text("offramp.topup.resume.button", "Resume top-up")
                            : text("offramp.topup.continue", "Review bridge"),
                        isEnabled: Offramp.validTopUpMicros(store.topUpAmount) != nil && !store.isLoading
                            && store.topUpValidatedMicros == Offramp.validTopUpMicros(store.topUpAmount)
                            && !store.isTopUpValidationLoading
                            && !store.isTopUpAmountInsufficient
                    ) {
                        store.send(.startTopUpTapped)
                    }
                }
            }
        }
    }

    private var topUpUsesFiat: Bool {
        store.quote != nil && store.selectedCorridor != nil
    }

    private var topUpValidationMessage: String? {
        guard Offramp.hasPositiveAmount(store.topUpAmount) else { return nil }
        guard Offramp.validTopUpMicros(store.topUpAmount) == nil else { return nil }
        return text("offramp.topup.limit.android", "Maximum 100 USDC per bridge.")
    }

    private var topUpAmountBinding: Binding<String> {
        Binding(
            get: { topUpUsesFiat ? store.topUpFiatAmount : store.topUpAmount },
            set: {
                store.send(topUpUsesFiat
                    ? .topUpFiatAmountChanged($0)
                    : .topUpAmountChanged($0))
            }
        )
    }

    private var bridgePreviewMessage: String {
        guard let preview = store.bridgePreview else {
            return text("offramp.bridge.preview.unavailable", "The bridge quote is unavailable. Review it again.")
        }
        var lines = [
            "\(preview.sourceAmount) \(preview.sourceAsset)",
            "→ \(preview.destinationAmount) \(preview.destinationAsset)"
        ]
        if let fee = preview.networkFee {
            lines.append("\(text("offramp.bridge.preview.fee", "Network fee")): \(fee) ZEC")
        }
        if preview.estimatedSeconds > 0 {
            lines.append("\(text("offramp.bridge.preview.time", "Estimated time")): \(preview.estimatedSeconds) s")
        }
        return lines.joined(separator: "\n")
    }

    private var progress: some View {
        VStack(spacing: 0) {
            ZappScreenHeader(title: store.latestProgress?.title ?? text("offramp.progress", "Payment in progress"))
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if store.progress.isEmpty {
                        ProgressView().tint(ZappColors.accent.color(colorScheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else {
                        ZappOfframpStepList(items: progressItems)
                    }
                    if let latest = store.latestProgress, latest.isTerminal {
                        callout(
                            title: latest.isSuccess
                                ? text("offramp.progress.success", "Complete")
                                : text("offramp.progress.stopped", "Payment stopped"),
                            detail: latest.detail ?? latest.title
                        )
                    }
                    if let error = store.errorMessage {
                        Text(error)
                            .zappFont(.caption, style: ZappColors.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
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

    private var progressItems: [ZappOfframpStepItem] {
        if store.bridgePreview != nil {
            let latest = store.latestProgress
            let terminal = latest?.isTerminal == true
            let failed = terminal && latest?.isSuccess == false
            return [
                ZappOfframpStepItem(
                    id: "bridge",
                    label: text("offramp.topup.progress.bridge", "Bridging from ZEC via NEAR"),
                    detail: latest?.kind == "bridging_funds" ? latest?.detail : nil,
                    status: terminal ? (failed ? .failed : .completed) : .inProgress
                ),
                ZappOfframpStepItem(
                    id: "arrived",
                    label: text("offramp.topup.progress.arrived", "Funds arrived on Base"),
                    detail: nil,
                    status: terminal && !failed ? .completed : .pending
                )
            ]
        }

        let latest = store.latestProgress
        let showsFunding = store.progress.contains { $0.kind == "bridging_funds" }
        var steps = [
            ("SELECTING_CIRCLE", text("offramp.progress.selecting", "Picking a merchant pool")),
            ("APPROVING_USDC", text("offramp.progress.approving", "Approving USDC")),
            ("PLACING_ORDER", text("offramp.progress.placing", "Placing the order")),
            ("WAITING_FOR_ACCEPTANCE", text("offramp.progress.acceptance", "Waiting for merchant to accept")),
            ("WAITING_FOR_PAYMENT_DETAILS", text("offramp.progress.scan", "Scan merchant QR")),
            ("SENDING_UPI", String(
                format: text("offramp.progress.sendingDetails", "Sending encrypted %@"),
                store.selectedCorridor?.paymentRail ?? "payment details"
            )),
            ("WAITING_FOR_COMPLETION", latest?.kind == "completed"
                ? text("offramp.progress.completed", "Payment complete")
                : text("offramp.progress.waiting", "Waiting for merchant payment"))
        ]
        if showsFunding {
            steps.insert(("FUNDING", text("offramp.progress.funding", "Bridging funds")), at: 1)
        }

        let currentStep = latest?.step ?? "SELECTING_CIRCLE"
        let currentIndex = steps.firstIndex { $0.0 == currentStep } ?? 0
        return steps.enumerated().map { index, step in
            let status: ZappOfframpStepStatus
            if latest?.kind == "completed" {
                status = .completed
            } else if latest?.kind == "failed" {
                status = index < currentIndex ? .completed : (index == currentIndex ? .failed : .pending)
            } else if index < currentIndex {
                status = .completed
            } else if index == currentIndex {
                status = .inProgress
            } else {
                status = .pending
            }
            return ZappOfframpStepItem(
                id: step.0,
                label: step.1,
                detail: index == currentIndex ? latest?.detail : nil,
                status: status
            )
        }
    }

    private var history: some View {
        VStack(spacing: 0) {
            ZappScreenHeader(title: text("offramp.history.title", "P2P transactions"))
            ScrollView {
                LazyVStack(spacing: 0) {
                    historyAccountSummary
                        .padding(.bottom, 16)
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
                Text(corridor.flag)
                    .font(.system(size: 25))
                    .frame(width: 30, height: 20)
                VStack(alignment: .leading, spacing: 3) {
                    Text(corridor.countryName).zappFont(.rowTitle, style: ZappColors.text)
                    Text("\(corridor.paymentRail) · \(corridor.currencyCode)")
                        .zappFont(.caption, style: ZappColors.textMuted)
                }
                Spacer()
                if corridor.currencyCode == store.draftCurrencyCode {
                    Asset.Assets.Icons.checkSolid.image
                        .zImage(width: 18, height: 18, style: ZappColors.accentText)
                        .frame(width: 18, height: 20)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func historyRow(_ item: OfframpHistoryModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("#\(item.id)").zappFont(.rowTitle, style: ZappColors.text)
                if let type = item.type {
                    Text(type.label.uppercased())
                        .zappFont(.caption, style: ZappColors.textMuted)
                }
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
            if item.canRecoverEscrow {
                ZappButton(title: text("offramp.history.recover", "Get funds back to ZEC"), variant: .ghost) {
                    store.send(.recoverTapped(item.id))
                }
            }
        }
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var historyAccountSummary: some View {
        if let account = store.account {
            VStack(alignment: .leading, spacing: 12) {
                accountAddressCard(account)
                ZappBorderedCard {
                    ZappSummaryRow(
                        label: String(localizable: .offrampHistoryBalance),
                        value: account.balanceDisplay.map { "\($0) USDC" } ?? "—"
                    )
                    if account.canRefundToZec {
                        ZappButton(title: String(localizable: .offrampHistoryRefund), variant: .ghost) {
                            store.send(.refundTapped)
                        }
                    } else if account.balanceMicros.flatMap({ Decimal(string: $0) }).map({ $0 > 0 }) == true {
                        Text(String(localizable: .offrampHistoryRefundBlocked))
                            .zappFont(.caption, style: ZappColors.textMuted)
                    }
                }
            }
        } else if store.isLoading {
            ProgressView()
        } else {
            Text(String(localizable: .offrampHistoryBalanceUnavailable))
                .zappFont(.caption, style: ZappColors.textMuted)
        }
    }

    private var paymentMethodInfo: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text("offramp.info.android.title", "How this works"))
                .zappFont(.sectionTitle, style: ZappColors.text)
            Text(text(
                "offramp.info.android.flow",
                "Enter the amount first. Zapp connects you to a merchant, then asks you to scan the merchant QR so the encrypted payment details can be sent."
            ))
            .zappFont(.body, style: ZappColors.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            Text(text(
                "offramp.info.android.privacy",
                "No KYC is required, and your funds leave from your shielded balance, so the merchant only sees the Base account that pays them, not your Zcash address."
            ))
            .zappFont(.body, style: ZappColors.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            Text(text(
                "offramp.info.android.estimate",
                "Estimated. Final amount locks in when the merchant accepts."
            ))
            .zappFont(.caption, style: ZappColors.textSubtle)
            .fixedSize(horizontal: false, vertical: true)
            ZappButton(title: text("general.ok", "OK")) { isPaymentInfoPresented = false }
                .padding(.top, 12)
        }
        .padding(.top, 24)
        .padding(.bottom, Design.Spacing.sheetBottomSpace)
    }

    private var topUpInfo: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text("offramp.info.android.title", "How this works"))
                .zappFont(.sectionTitle, style: ZappColors.text)
            Text(text(
                "offramp.topup.info.android",
                "We bridge your ZEC to Base, where merchant payments settle. This takes a few minutes. After that, paying is instant and you can reuse the balance."
            ))
            .zappFont(.body, style: ZappColors.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            if let account = store.account { accountAddressCard(account) }
            ZappButton(title: text("general.ok", "OK")) { isTopUpInfoPresented = false }
                .padding(.top, 12)
        }
        .padding(.top, 24)
        .padding(.bottom, Design.Spacing.sheetBottomSpace)
    }

    private func infoButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Asset.Assets.infoCircle.image
                .zImage(width: 20, height: 20, style: ZappColors.text)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.zappPress)
        .accessibilityLabel(text("offramp.paymentMethod.infoButton", "How P2P payments work"))
    }

    private func accountAddressCard(_ account: OfframpAccountModel) -> some View {
        ZappBorderedCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(text("offramp.account.label", "Your Base account"))
                    .zappFont(.caption, style: ZappColors.textMuted)
                HStack(spacing: 10) {
                    ZappExplorerLink(address: account.address, url: account.explorerURL)
                    Spacer()
                    Button { store.send(.copyAccountAddressTapped) } label: {
                        Asset.Assets.copy.image
                            .zImage(width: 20, height: 20, style: store.isAddressCopied ? ZappColors.success : ZappColors.textMuted)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.zappPress)
                    .accessibilityLabel(text("offramp.account.copy", "Copy Base account"))
                }
            }
        }
    }

    private func callout(title: String, detail: String) -> some View {
        ZappBorderedCard {
            VStack(alignment: .leading, spacing: 6) {
                Rectangle().fill(ZappColors.accent.color(colorScheme)).frame(width: 3, height: 20)
                Text(title).zappFont(.rowTitle, style: ZappColors.text)
                Text(detail).zappFont(.body, style: ZappColors.textMuted)
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        ZappSummaryRow(label: label, value: value)
    }

    private func formatMicros(_ value: String) -> String {
        let decimal = Decimal(string: value) ?? 0
        return NSDecimalNumber(decimal: decimal / 1_000_000).stringValue
    }

    private func text(_ key: String, _ fallback: String) -> String {
        Bundle.main.localizedString(forKey: key, value: fallback, table: nil)
    }
}
