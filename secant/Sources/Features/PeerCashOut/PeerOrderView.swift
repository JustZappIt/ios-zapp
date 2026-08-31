// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import SwiftUI

struct PeerOrderView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    @Perception.Bindable var store: StoreOf<PeerOrderDetail>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: String(localizable: .peerOrderTitle)) {
                    Button { store.send(.refreshTapped) } label: {
                        Asset.Assets.refreshCCW.image
                            .zImage(width: 20, height: 20, style: ZappColors.text)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.zappPress)
                    .accessibilityLabel(String(localizable: .peerOrderRefresh))
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let order = store.order {
                            phaseHeader(order)
                            ZappCompactLedger(rows: store.amountRows)
                            if let message = store.readErrorMessage { staleNote(message) }
                            if let failure = store.actionFailure { actionFailureCard(failure) }
                            controls(order)
                            buyerLegs(order)
                            provenance(order)
                        } else if store.isLoading {
                            ProgressView()
                                .tint(ZappColors.accent.color(colorScheme))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else if let message = store.readErrorMessage {
                            staleNote(message)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                }

                ZappBottomActionBar(onBack: { store.send(.backTapped) })
            }
            .applyScreenBackground()
            .onAppear { store.send(.onAppear) }
            .onDisappear { store.send(.onDisappear) }
        }
    }

    private func phaseHeader(_ order: PeerOrder) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZappStatusChip(text: order.phase.label, variant: chipVariant(order.phase))

            Text(String(localizable: .peerUsdcAmount(order.remaining.display)))
                .zappFont(.display, style: ZappColors.text)

            Text(String(localizable: .peerOrderRemainingCaption))
                .zappFont(.caption, style: ZappColors.textMuted)

            // Still valid and still the user's, but below the floor Peer's orderbook lists, so
            // nobody is browsing it. Silence here reads as "no buyers want it".
            if order.isHiddenFromBuyers {
                Text(String(localizable: .peerOrderHiddenFromBuyers))
                    .zappFont(.caption, style: ZappColors.accentText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(ZappColors.accentSoft.color(colorScheme))
            }
        }
    }

    @ViewBuilder
    private func controls(_ order: PeerOrder) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.offersWithdrawal {
                Text(String(localizable: .peerOrderWithdrawExplainer(order.withdrawable.display)))
                    .zappFont(.caption, style: ZappColors.textMuted)

                ZappButton(
                    title: String(localizable: .peerOrderWithdraw(order.withdrawable.display))
                ) { store.send(.withdrawTapped) }
            } else if store.offersMatchingToggle {
                Text(String(localizable: .peerOrderMatchingExplainer))
                    .zappFont(.caption, style: ZappColors.textMuted)

                ZappButton(
                    title: order.acceptingIntents
                        ? String(localizable: .peerOrderPauseMatching)
                        : String(localizable: .peerOrderResumeMatching),
                    variant: .ghost
                ) { store.send(.matchingToggleTapped) }
            } else if store.isBusy {
                // The escrow has already moved; the figures above have not caught up. Saying so is
                // better than a button that would act on numbers the chain has replaced.
                Text(String(localizable: .peerOrderActionSettling))
                    .zappFont(.caption, style: ZappColors.textMuted)
            }
        }
    }

    @ViewBuilder
    private func buyerLegs(_ order: PeerOrder) -> some View {
        if !order.buyerLegs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localizable: .peerOrderBuyersLabel))
                    .zappFont(.eyebrow, style: ZappColors.textMuted)

                ForEach(order.buyerLegs) { leg in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localizable: .peerUsdcAmount(leg.amount.display)))
                                .zappFont(.rowTitle, style: ZappColors.text)
                            if let amount = leg.paymentAmount, let currency = leg.paymentCurrencyCode {
                                Text("\(amount) \(currency)")
                                    .zappFont(.caption, style: ZappColors.textMuted)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        ZappStatusChip(text: leg.outcome.label, variant: legVariant(leg.outcome))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(ZappColors.surface.color(colorScheme))
                    .overlay(Rectangle().strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1))
                }
            }
        }
    }

    @ViewBuilder
    private func provenance(_ order: PeerOrder) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let openedAt = order.openedAt {
                Text(
                    String(
                        localizable: .peerOrderOpened(openedAt.formatted(date: .abbreviated, time: .shortened))
                    )
                )
                .zappFont(.caption, style: ZappColors.textMuted)
            }

            if let url = order.explorerURL {
                ZappButton(title: String(localizable: .peerOrderViewOnExplorer), variant: .ghost) {
                    openURL(url)
                }
            }
        }
    }

    private func staleNote(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localizable: .peerOrderStaleTitle))
                .zappFont(.rowTitle, style: ZappColors.text)
            Text(message).zappFont(.caption, style: ZappColors.textMuted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ZappColors.surfaceAlt.color(colorScheme))
        .overlay(Rectangle().strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1))
    }

    private func actionFailureCard(_ failure: PeerFailure) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(failure.message)
                .zappFont(.body, style: ZappColors.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            ZappButton(title: String(localizable: .generalOk), variant: .ghost) {
                store.send(.dismissActionErrorTapped)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ZappColors.dangerSoft.color(colorScheme))
        .overlay(Rectangle().strokeBorder(ZappColors.danger.color(colorScheme), lineWidth: 1))
    }

    private func chipVariant(_ phase: PeerOrder.Phase) -> ZappChipVariant {
        switch phase {
        case .waiting, .partlySold: return .accent
        case .buyerPaying: return .success
        case .sold: return .success
        case .paused: return .muted
        case .closed: return .muted
        }
    }

    private func legVariant(_ outcome: PeerBuyerLeg.Outcome) -> ZappChipVariant {
        switch outcome {
        case .paying: return .accent
        case .paid: return .success
        case .outOfTime: return .danger
        case .backedOut, .timedOut, .unknown: return .muted
        }
    }
}

#Preview {
    PeerOrderView(
        store: Store(
            initialState: PeerOrderDetail.State(depositID: "0x777777779d229cdf3110e9de47943791c26300ef_1")
        ) { PeerOrderDetail() }
    )
    .applyScreenBackground()
}
