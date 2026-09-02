// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import SwiftUI
@preconcurrency import ZcashLightClientKit

struct GiftCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    @Perception.Bindable var store: StoreOf<GiftCard>

    @State private var isInfoPresented = false

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: String(localizable: .giftCardTitle), subtitle: subtitle) {
                    headerRight
                }

                GeometryReader { geometry in
                    ScrollView {
                        VStack(spacing: 0) {
                            stageContent
                            Spacer(minLength: 16)
                        }
                        .frame(minHeight: geometry.size.height, alignment: .top)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                    }
                }

                bottomBar
            }
            .applyScreenBackground()
            .sheet(isPresented: $isInfoPresented) { fundingInfoSheet }
            .background(shareMount)
            .onAppear { store.send(.onAppear) }
        }
    }

    private var subtitle: String {
        switch store.visibleStage {
        case .details: return String(localizable: .giftCardSubtitleDetails)
        case .preparing: return String(localizable: .giftCardPreparing)
        case .review: return String(localizable: .giftCardSubtitleReview)
        case .funding: return String(localizable: .giftCardSubtitleFunding)
        case .ready: return String(localizable: .giftCardSubtitleReady)
        case .unavailable: return String(localizable: .giftCardSubtitleUnavailable)
        }
    }

    @ViewBuilder
    private var headerRight: some View {
        HStack(spacing: Design.Spacing._md) {
            if store.canOpenSavedCards {
                Button {
                    store.send(.openSavedCardsTapped)
                } label: {
                    Text(String(localizable: .giftCardListOpen))
                        .zappFont(.buttonSmall, style: ZappColors.accent)
                }
                .buttonStyle(.zappPress)
            }
            if store.visibleStage == .review {
                ZappInfoButton(
                    accessibilityLabel: String(localizable: .giftCardReviewWarningTitle)
                ) { isInfoPresented = true }
            }
        }
    }

    @ViewBuilder
    private var stageContent: some View {
        switch store.visibleStage {
        case .details:
            detailsStage
        case .preparing:
            preparingStage
        case .review:
            reviewStage
        case .funding:
            fundingStage
        case .ready:
            readyStage
        case .unavailable:
            unavailableStage
        }
    }

    // MARK: - Details

    private var detailsStage: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._2xl) {
            podium(isTurning: false, fiatOnFace: false)
            amountGroup
            messageGroup
            expiryControl
            errorLine
        }
    }

    private func podium(isTurning: Bool, fiatOnFace: Bool) -> some View {
        let amount = store.previewAmount ?? .zero
        let tier = giftCardTier(amountZatoshi: amount.amount, isSettled: false)
        return GiftCardPodium(
            stock: tier.stock,
            amountText: giftAmountText(amount),
            fiatText: store.fiatText,
            fiatOnFace: fiatOnFace,
            message: store.message.isEmpty ? nil : store.message,
            isTurning: isTurning,
            flourishKey: tierFlourishKey(tier)
        )
        .frame(maxWidth: .infinity)
    }

    private func tierFlourishKey(_ tier: GiftCardTier) -> Int {
        // A tier crossing plays one full flourish turn; the key only has to change per rung.
        switch tier {
        case .clay: return 0
        case .slate: return 1
        case .cinnabar: return 2
        case .vermilion: return 3
        case .copper: return 4
        case .amber: return 5
        case .tiger: return 6
        case .signature: return 7
        case .dragon: return 8
        case .spent: return 9
        }
    }

    private var amountGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localizable: .giftCardAmountLabel))
                .zappFont(.eyebrow, style: ZappColors.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .center, spacing: 8) {
                Text(String(localizable: .giftCardAmountSymbol))
                    .zappFont(.displaySecondary, style: ZappColors.textMuted)

                TextField("0", text: $store.amountInput)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                    .zappFont(.display, style: ZappColors.text)
                    .accessibilityLabel(String(localizable: .giftCardAmountLabel))

                if let spendable = store.spendableBalanceText {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(localizable: .giftCardAmountBalanceLabel))
                            .zappFont(.caption, style: ZappColors.textSubtle)
                        Text(spendable)
                            .zappFont(.caption, style: ZappColors.textMuted)
                    }
                }
            }
            .padding(.vertical, 4)

            Rectangle()
                .fill(
                    isAmountInvalid
                        ? ZappColors.danger.color(colorScheme)
                        : ZappColors.accent.color(colorScheme)
                )
                .frame(height: 2)

            if let fiat = store.fiatText {
                Text(fiat)
                    .zappFont(.body, style: ZappColors.textMuted)
                    .padding(.top, 2)
            }

            if isAmountInvalid {
                Text(String(localizable: .giftCardAmountErrorInvalid))
                    .zappFont(.caption, style: ZappColors.danger)
            }

            Text(String(localizable: .giftCardAmountHint))
                .zappFont(.caption, style: ZappColors.textSubtle)
                .padding(.top, 2)
        }
    }

    private var isAmountInvalid: Bool {
        !store.amountInput.isEmpty && store.typedAmount == nil
    }

    private var messageGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(localizable: .giftCardMessageLabel))
                    .zappFont(.eyebrow, style: ZappColors.textMuted)
                Spacer()
                Text(String(localizable: .giftCardMessageCounter(store.messageGraphemes, GiftMessage.maxGraphemes)))
                    .zappFont(
                        .caption,
                        style: store.messageGraphemes > GiftMessage.maxGraphemes ? ZappColors.danger : ZappColors.textSubtle
                    )
            }

            TextField(String(localizable: .giftCardMessagePlaceholder), text: $store.message, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.plain)
                .zappFont(.rowTitle, style: ZappColors.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(minHeight: 44)
                .background(ZappColors.surfaceInput.color(colorScheme))
                .overlay(
                    Rectangle().strokeBorder(
                        store.isMessageTooLong
                            ? ZappColors.danger.color(colorScheme)
                            : ZappColors.border.color(colorScheme),
                        lineWidth: 1
                    )
                )
                .accessibilityLabel(String(localizable: .giftCardMessageLabel))

            if store.isMessageTooLong {
                Text(String(localizable: .giftCardMessageErrorTooLong))
                    .zappFont(.caption, style: ZappColors.danger)
            }
        }
    }

    private var expiryControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            Menu {
                ForEach(GiftCard.Expiry.allCases, id: \.rawValue) { choice in
                    Button(expiryText(choice)) { store.send(.expiryChanged(choice)) }
                }
            } label: {
                Text(String(localizable: .giftCardExpiryCompact(expiryText(store.expiry))))
                    .zappFont(.caption, style: ZappColors.textMuted)
            }
            .accessibilityLabel(String(localizable: .giftCardExpiryLabel))

            if store.expiry != .never {
                Text(String(localizable: .giftCardExpiryHint))
                    .zappFont(.caption, style: ZappColors.textSubtle)
            }
        }
    }

    private func expiryText(_ expiry: GiftCard.Expiry) -> String {
        expiry == .never
            ? String(localizable: .giftCardExpiryNone)
            : String(localizable: .giftCardExpiryDays(expiry.rawValue))
    }

    // MARK: - Preparing / Funding

    private var preparingStage: some View {
        VStack(spacing: Design.Spacing._xl) {
            Spacer(minLength: 64)
            ProgressView()
            Text(String(localizable: .giftCardPreparing))
                .zappFont(.body, style: ZappColors.textMuted)
            Spacer(minLength: 64)
        }
        .frame(maxWidth: .infinity)
    }

    private var fundingStage: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._2xl) {
            podium(isTurning: true, fiatOnFace: false)
            sweepBar
            Text(String(localizable: .giftCardFundingNote))
                .zappFont(.caption, style: ZappColors.textMuted)
            VStack(alignment: .leading, spacing: Design.Spacing._lg) {
                fundingStep(String(localizable: .giftCardStepMinted), state: .done)
                fundingStep(String(localizable: .giftCardStepFunding), state: .active)
                fundingStep(String(localizable: .giftCardStepReady), state: .pending)
            }
        }
    }

    private enum StepState { case done, active, pending }

    private func fundingStep(_ title: String, state: StepState) -> some View {
        HStack(spacing: Design.Spacing._md) {
            Rectangle()
                .fill(stepColor(state).color(colorScheme))
                .frame(width: 8, height: 8)
            Text(title)
                .zappFont(.rowSubtitle, style: state == .pending ? ZappColors.textSubtle : ZappColors.text)
        }
    }

    private func stepColor(_ state: StepState) -> ZappColors {
        switch state {
        case .done: return .success
        case .active: return .accent
        case .pending: return .border
        }
    }

    /// An indeterminate sweep: a 30%-width accent block gliding along a bordered track.
    private var sweepBar: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
            GeometryReader { proxy in
                let width = proxy.size.width
                let blockWidth = width * 0.3
                Rectangle()
                    .fill(ZappColors.accent.color(colorScheme))
                    .frame(width: blockWidth)
                    .offset(x: (width + blockWidth) * phase - blockWidth)
            }
            .frame(height: 3)
            .background(ZappColors.surfaceAlt.color(colorScheme))
            .clipped()
        }
    }

}

extension GiftCardView {
    // MARK: - Review

    private var reviewStage: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xl) {
            ZappGroupHeader(text: String(localizable: .giftCardReviewLabel))
            ZappBorderedCard {
                VStack(spacing: Design.Spacing._lg) {
                    if let quote = store.quote {
                        ZappSummaryRow(
                            label: String(localizable: .giftCardReviewAmount),
                            value: giftAmountText(quote.cardAmount)
                        )
                        ZappSummaryRow(
                            label: String(localizable: .giftCardReviewReserve),
                            value: giftAmountText(quote.claimFeeReserve)
                        )
                        ZappSummaryRow(
                            label: String(localizable: .giftCardReviewNetworkFee),
                            value: giftAmountText(quote.networkFee)
                        )
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(String(localizable: .giftCardReviewTotal))
                                .zappFont(.caption, style: ZappColors.textMuted)
                            Spacer(minLength: 8)
                            Text(giftAmountText(quote.total))
                                .zappFont(.body, style: ZappColors.accent)
                        }
                        if let message = quote.card.message {
                            ZappSummaryRow(label: String(localizable: .giftCardReviewMessageLabel), value: message)
                        }
                    }
                }
            }
            errorLine
        }
    }

    // MARK: - Ready / Unavailable

    private var readyStage: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._2xl) {
            ZappSuccessHeader(
                title: String(localizable: .giftCardReadyTitle),
                subtitle: String(localizable: .giftCardReadySubtitle)
            )
            podium(isTurning: false, fiatOnFace: true)
            linkGroup
            errorLine
        }
    }

    private var linkGroup: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._lg) {
            Text(String(localizable: .giftCardReadyLinkLabel))
                .zappFont(.eyebrow, style: ZappColors.textMuted)
            ZappBorderedCard {
                // Presentation only — the full link is what shares. Concealed the moment the app
                // leaves the foreground: the link is the money.
                Text(scenePhase == .active ? ellipsizedLink : "••••••••")
                    .zappFont(.mono, style: ZappColors.text)
                    .lineLimit(1)
            }
            warningRow(String(localizable: .giftCardReadyBearer))
            warningRow(String(localizable: .giftCardReadyClaimable))
        }
    }

    private var ellipsizedLink: String {
        guard let link = store.link else { return "" }
        let withoutScheme = link.replacingOccurrences(of: "https://", with: "")
        guard withoutScheme.count > 31 else { return withoutScheme }
        return "\(withoutScheme.prefix(20))…\(withoutScheme.suffix(8))"
    }

    private func warningRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Design.Spacing._md) {
            Rectangle()
                .fill(ZappColors.accent.color(colorScheme))
                .frame(width: 3)
            Text(text)
                .zappFont(.caption, style: ZappColors.textMuted)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var unavailableStage: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._2xl) {
            podium(isTurning: false, fiatOnFace: false)
            Text(String(localizable: .giftCardUnavailableBody))
                .zappFont(.body, style: ZappColors.textMuted)
            errorLine
        }
    }

    @ViewBuilder
    private var errorLine: some View {
        if let error = store.error {
            Text(errorText(error))
                .zappFont(.caption, style: ZappColors.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func errorText(_ error: GiftCard.FlowError) -> String {
        switch error {
        case .amountInvalid: return String(localizable: .giftCardAmountErrorInvalid)
        case .messageTooLong: return String(localizable: .giftCardMessageErrorTooLong)
        case .insufficientFunds: return String(localizable: .giftCardErrorInsufficient)
        case .keystoneUnsupported: return String(localizable: .giftCardErrorKeystone)
        case .unsupportedNetwork: return String(localizable: .giftCardErrorNetwork)
        case .chainTipUnavailable: return String(localizable: .giftCardErrorChainTip)
        case .persistFailed: return String(localizable: .giftCardErrorPersist)
        case .mintFailed: return String(localizable: .giftCardErrorMint)
        case .proposalFailed: return String(localizable: .giftCardErrorProposal)
        case .authenticationFailed: return String(localizable: .giftCardErrorAuth)
        case .submitUncertain: return String(localizable: .giftCardErrorSubmitUncertain)
        case .shareFailed: return String(localizable: .giftCardErrorShare)
        }
    }

}

extension GiftCardView {
    // MARK: - Chrome

    @ViewBuilder
    private var bottomBar: some View {
        switch store.visibleStage {
        case .details:
            ZappBottomActionBar(onBack: { store.send(.backTapped) }) {
                ZappButton(
                    title: String(localizable: .giftCardContinue),
                    isEnabled: store.canContinue
                ) { store.send(.reviewTapped) }
            }
        case .review:
            ZappBottomActionBar(onBack: { store.send(.backTapped) }, isBackEnabled: store.isBackEnabled) {
                ZappButton(
                    title: store.isAuthenticating
                        ? String(localizable: .giftCardAuthenticating)
                        : String(localizable: .giftCardReviewConfirm),
                    isEnabled: store.canConfirm
                ) { store.send(.fundTapped) }
            }
        case .ready:
            ZappBottomActionBar(onBack: { store.send(.backTapped) }) {
                ZappButton(title: String(localizable: .giftCardReadyShare)) { store.send(.shareTapped) }
            }
        case .unavailable:
            ZappBottomActionBar(onBack: { store.send(.backTapped) }) { EmptyView() }
        case .preparing, .funding:
            // No way out while a broadcast may be in flight: the back chrome disappears entirely,
            // and the swipe-back gesture is Root's to withhold for path screens.
            EmptyView()
        }
    }

    /// Mounted on a background subview so it never competes with the info sheet — one `.sheet`
    /// per view.
    @ViewBuilder
    private var shareMount: some View {
        if let link = store.shareLink {
            UIShareDialogView(
                activityItems: [link],
                completion: {},
                onOutcome: { completed in store.send(.shareFinished(completed)) }
            )
        }
    }

    private var fundingInfoSheet: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xl) {
            Text(String(localizable: .giftCardReviewWarningTitle))
                .zappFont(.sectionTitle, style: ZappColors.text)
            VStack(alignment: .leading, spacing: Design.Spacing._lg) {
                warningRow(String(localizable: .giftCardReviewWarningIrreversible))
                warningRow(String(localizable: .giftCardReviewWarningBearer))
                warningRow(String(localizable: .giftCardReviewWarningBackup))
                warningRow(String(localizable: .giftCardReviewWarningDelay))
            }
            ZappButton(title: String(localizable: .giftClaimDone)) { isInfoPresented = false }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .applyScreenBackground()
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    GiftCardView(
        store: Store(initialState: GiftCard.State()) {
            GiftCard()
        }
    )
}
