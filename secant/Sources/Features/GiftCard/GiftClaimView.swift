// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import SwiftUI
@preconcurrency import ZcashLightClientKit

struct GiftClaimView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<GiftClaim>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: String(localizable: .giftClaimTitle), subtitle: subtitle)

                GeometryReader { geometry in
                    ScrollView {
                        // The card is the subject, not a form: content rides vertically centred.
                        VStack(spacing: Design.Spacing._2xl) {
                            stageContent
                        }
                        .frame(minHeight: geometry.size.height, alignment: .center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                    }
                }

                bottomBar
            }
            .applyScreenBackground()
            .onAppear { store.send(.onAppear) }
            .onDisappear { store.send(.teardown) }
        }
    }

    private var subtitle: String {
        switch store.stage {
        case .loading, .preview, .consent: return String(localizable: .giftClaimSubtitlePreview)
        case .needsWallet: return String(localizable: .giftClaimSubtitleNeedsWallet)
        case .claiming: return String(localizable: .giftClaimSubtitleClaiming)
        case .done: return String(localizable: .giftClaimSubtitleDone)
        case .claimConfirming: return String(localizable: .giftClaimSubtitleConfirming)
        case .pendingConfirmations: return String(localizable: .giftClaimSubtitleWaiting)
        case .awaitingFunding: return String(localizable: .giftClaimSubtitleWaiting)
        case .alreadyClaimed: return String(localizable: .giftClaimSubtitleAlreadyClaimed)
        }
    }

    @ViewBuilder
    private var stageContent: some View {
        switch store.stage {
        case .loading:
            if store.payload == nil {
                ProgressView()
            } else {
                podium
                sweepBar
                Text(String(localizable: .giftClaimConnecting))
                    .zappFont(.body, style: ZappColors.textMuted)
            }

        case .needsWallet:
            podium
            VStack(alignment: .leading, spacing: Design.Spacing._md) {
                Text(String(localizable: .giftClaimNeedsWalletTitle))
                    .zappFont(.sectionTitle, style: ZappColors.text)
                Text(String(localizable: .giftClaimNeedsWalletBody))
                    .zappFont(.body, style: ZappColors.textMuted)
            }
            errorLine

        case .preview:
            podium
            previewDetails
            if store.isPastExpiry {
                Text(String(localizable: .giftClaimExpiredNote))
                    .zappFont(.caption, style: ZappColors.textSubtle)
            }
            errorLine

        case .consent(let blocksToScan):
            podium
            VStack(alignment: .leading, spacing: Design.Spacing._md) {
                Text(String(localizable: .giftClaimConsentTitle))
                    .zappFont(.sectionTitle, style: ZappColors.text)
                Text(String(localizable: .giftClaimConsentBody(blockCountText(blocksToScan), durationText(blocksToScan))))
                    .zappFont(.body, style: ZappColors.textMuted)
            }
            errorLine

        case .claiming:
            podium
            VStack(alignment: .leading, spacing: Design.Spacing._md) {
                Text(String(localizable: .giftClaimProgressSyncing))
                    .zappFont(.body, style: ZappColors.text)
                progressBar
                if let remaining = blocksRemaining {
                    Text(String(localizable: .giftClaimProgressRemaining(remaining)))
                        .zappFont(.caption, style: ZappColors.textSubtle)
                }
                Text(String(localizable: .giftClaimProgressNote))
                    .zappFont(.caption, style: ZappColors.textMuted)
            }

        case .done:
            ZappSuccessHeader(
                title: String(localizable: .giftClaimDoneTitle),
                subtitle: String(localizable: .giftClaimDoneSubtitle(amountText))
            )
            podium

        case .claimConfirming:
            podium
            VStack(alignment: .leading, spacing: Design.Spacing._md) {
                Text(String(localizable: .giftClaimConfirmingTitle))
                    .zappFont(.sectionTitle, style: ZappColors.text)
                confirmationBar
                if let confirmations = store.confirmations {
                    Text(String(localizable: .giftClaimPendingCount(confirmations, store.requiredConfirmations)))
                        .zappFont(.caption, style: ZappColors.textSubtle)
                }
                Text(String(localizable: .giftClaimConfirmingBody))
                    .zappFont(.body, style: ZappColors.textMuted)
            }
            errorLine

        case .pendingConfirmations:
            podium
            VStack(alignment: .leading, spacing: Design.Spacing._md) {
                Text(String(localizable: .giftClaimPendingTitle))
                    .zappFont(.sectionTitle, style: ZappColors.text)
                confirmationBar
                if let confirmations = store.confirmations {
                    Text(String(localizable: .giftClaimPendingCount(confirmations, store.requiredConfirmations)))
                        .zappFont(.caption, style: ZappColors.textSubtle)
                }
                Text(String(localizable: .giftClaimPendingBody))
                    .zappFont(.body, style: ZappColors.textMuted)
            }

        case .awaitingFunding:
            podium
            VStack(alignment: .leading, spacing: Design.Spacing._md) {
                Text(String(localizable: .giftClaimAwaitingFundingTitle))
                    .zappFont(.sectionTitle, style: ZappColors.text)
                Text(String(localizable: .giftClaimAwaitingFundingBody))
                    .zappFont(.body, style: ZappColors.textMuted)
            }
            errorLine

        case .alreadyClaimed:
            podium
            VStack(alignment: .leading, spacing: Design.Spacing._md) {
                Text(String(localizable: .giftClaimAlreadyClaimedTitle))
                    .zappFont(.sectionTitle, style: ZappColors.text)
                Text(String(localizable: .giftClaimAlreadyClaimedBody))
                    .zappFont(.body, style: ZappColors.textMuted)
            }
        }
    }

    @ViewBuilder
    private var podium: some View {
        if let amount = store.amount {
            let settled = store.stage == .alreadyClaimed
            let tier = giftCardTier(amountZatoshi: amount.amount, isSettled: settled)
            GiftCardPodium(
                stock: tier.stock,
                amountText: giftAmountText(amount),
                fiatText: store.fiatText,
                fiatOnFace: false,
                message: store.payload?.message,
                caption: String(localizable: .giftClaimPodiumCaption),
                // Nothing here is settled until the claim mines, so the card keeps turning.
                isTurning: isPodiumTurning
            )
            .frame(maxWidth: .infinity)
            if let fiat = store.fiatText {
                Text(fiat)
                    .zappFont(.caption, style: ZappColors.textMuted)
            }
        }
    }

    private var isPodiumTurning: Bool {
        switch store.stage {
        case .loading, .claiming, .claimConfirming, .pendingConfirmations:
            return true
        default:
            return false
        }
    }

    /// The face clips the message at two lines; the recipient must be able to read all of it.
    @ViewBuilder
    private var previewDetails: some View {
        if store.payload?.message != nil || store.payload?.expiresAt != nil {
            ZappBorderedCard {
                VStack(alignment: .leading, spacing: Design.Spacing._lg) {
                    if let message = store.payload?.message {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localizable: .giftClaimMessageLabel))
                                .zappFont(.eyebrow, style: ZappColors.textMuted)
                            Text(message)
                                .zappFont(.body, style: ZappColors.text)
                        }
                    }
                    if let expiry = expiryDisplay {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localizable: .giftCardExpiryLabel))
                                .zappFont(.eyebrow, style: ZappColors.textMuted)
                            Text(expiry)
                                .zappFont(.body, style: ZappColors.text)
                        }
                    }
                }
            }
        }
    }

    private var expiryDisplay: String? {
        guard let raw = store.payload?.expiresAt else { return nil }
        guard let date = GiftLinkCodec.parseInstant(raw) else { return nil }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private var amountText: String {
        store.amount.map(giftAmountText) ?? ""
    }

    private func blockCountText(_ blocks: Int64) -> String {
        blocks.formatted(.number.grouping(.automatic))
    }

    /// A rough duration at 75 seconds per block, rendered in hours or days.
    private func durationText(_ blocks: Int64) -> String {
        let seconds = Double(blocks) * 75
        let hours = Int((seconds / 3600).rounded(.up))
        if hours < 48 {
            return String(localizable: .giftClaimConsentDurationHours(hours))
        }
        return String(localizable: .giftClaimConsentDurationDays(Int((seconds / 86_400).rounded(.up))))
    }

    private var blocksRemaining: Int? {
        guard
            let progress = store.progress,
            let scanned = progress.scannedHeight,
            let tip = progress.tipHeight,
            tip > scanned
        else { return nil }
        return tip - scanned
    }

    private var progressBar: some View {
        Group {
            if let fraction = store.progress?.fraction, fraction > 0 {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(ZappColors.accent.color(colorScheme))
                        .frame(width: proxy.size.width * CGFloat(min(fraction, 1)))
                }
                .frame(height: 3)
                .background(ZappColors.surfaceAlt.color(colorScheme))
            } else {
                // The SDK reports zero before measuring anything, and a bar pinned at 0% reads
                // as broken where a sweep reads as working.
                sweepBar
            }
        }
    }

    private var confirmationBar: some View {
        Group {
            if let confirmations = store.confirmations, store.requiredConfirmations > 0 {
                let fraction = CGFloat(confirmations) / CGFloat(store.requiredConfirmations)
                GeometryReader { proxy in
                    Rectangle()
                        .fill(ZappColors.accent.color(colorScheme))
                        .frame(width: proxy.size.width * min(fraction, 1))
                }
                .frame(height: 3)
                .background(ZappColors.surfaceAlt.color(colorScheme))
            } else {
                sweepBar
            }
        }
    }

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

    @ViewBuilder
    private var errorLine: some View {
        if let error = store.error {
            Text(errorText(error))
                .zappFont(.caption, style: ZappColors.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func errorText(_ error: GiftClaim.ClaimError) -> String {
        switch error {
        case .malformedLink: return String(localizable: .giftClaimErrorLink)
        case .wrongNetwork: return String(localizable: .giftClaimErrorNetwork)
        case .birthdayAboveTip: return String(localizable: .giftClaimErrorFuture)
        case .newerFormat: return String(localizable: .giftClaimErrorNewerFormat)
        case .walletNotReady: return String(localizable: .giftClaimErrorNotReady)
        case .linkUnavailable: return String(localizable: .giftClaimErrorUnavailable)
        case .notBroadcast: return String(localizable: .giftClaimErrorNotBroadcast)
        case .underfunded: return String(localizable: .giftClaimErrorUnderfunded)
        case .unreachable: return String(localizable: .giftClaimErrorUnreachable)
        case .scanStalled: return String(localizable: .giftClaimErrorScanStalled)
        case .paramsUnavailable: return String(localizable: .giftClaimErrorParams)
        case .failed: return String(localizable: .giftClaimErrorFailed)
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        switch store.stage {
        case .loading:
            ZappBottomActionBar(onBack: { store.send(.doneTapped) }) { EmptyView() }

        case .needsWallet:
            ZappBottomActionBar(onBack: { store.send(.doneTapped) }) {
                ZappButton(title: String(localizable: .giftClaimNeedsWalletAction)) {
                    store.send(.createWalletTapped)
                }
            }

        case .preview:
            ZappBottomActionBar(onBack: { store.send(.doneTapped) }) {
                if store.error == .linkUnavailable {
                    ZappButton(title: String(localizable: .giftClaimDone)) { store.send(.doneTapped) }
                } else if store.error != nil && store.payload == nil {
                    ZappButton(title: String(localizable: .giftClaimDone)) { store.send(.doneTapped) }
                } else {
                    ZappButton(title: String(localizable: .giftClaimClaim)) { store.send(.claimTapped) }
                }
            }

        case .consent:
            // Back is decline: no scan starts.
            ZappBottomActionBar(onBack: { store.send(.doneTapped) }) {
                ZappButton(title: String(localizable: .giftClaimConsentConfirm)) { store.send(.consentConfirmed) }
            }

        case .claiming:
            if store.canStopClaim {
                ZappBottomActionBar(onBack: {}, isBackEnabled: false) {
                    ZappButton(title: String(localizable: .giftClaimStopScan), variant: .secondary) {
                        store.send(.stopScanTapped)
                    }
                }
            } else {
                // The submit tail is in flight: no way out, nothing to press.
                EmptyView()
            }

        case .done:
            ZappBottomActionBar(onBack: { store.send(.doneTapped) }) {
                ZappButton(title: String(localizable: .giftClaimDone)) { store.send(.doneTapped) }
            }

        case .claimConfirming:
            ZappBottomActionBar(onBack: { store.send(.doneTapped) }) {
                ZappButton(title: String(localizable: .giftClaimConfirmingRecheck)) { store.send(.retryTapped) }
            }

        case .pendingConfirmations:
            // The screen re-checks itself; a Try-again here would frame a wait as a dead end.
            ZappBottomActionBar(onBack: { store.send(.doneTapped) }) { EmptyView() }

        case .awaitingFunding:
            ZappBottomActionBar(onBack: { store.send(.doneTapped) }) {
                ZappButton(title: String(localizable: .giftClaimRetry)) { store.send(.retryTapped) }
            }

        case .alreadyClaimed:
            ZappBottomActionBar(onBack: { store.send(.doneTapped) }) {
                ZappButton(title: String(localizable: .giftClaimDone)) { store.send(.doneTapped) }
            }
        }
    }
}

#Preview {
    GiftClaimView(
        store: Store(initialState: GiftClaim.State()) {
            GiftClaim()
        }
    )
}
