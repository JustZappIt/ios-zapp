// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import SwiftUI

struct P2pActivityView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<P2pActivity>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: String(localizable: .p2pActivityTitle))

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        accountSummary.padding(.bottom, 16)

                        if store.showsFilters {
                            ZappSegmentedSelector(
                                options: P2pActivity.State.Filter.allCases.map(\.label),
                                selectedIndex: selectedFilterIndex
                            ) { index in
                                store.send(.filterTapped(P2pActivity.State.Filter.allCases[index]))
                            }
                            .padding(.bottom, 16)
                        }

                        if let error = store.errorMessage {
                            Text(error)
                                .zappFont(.caption, style: ZappColors.danger)
                                .padding(.bottom, 12)
                        }

                        if store.entries.isEmpty && !store.isLoading {
                            Text(String(localizable: .p2pActivityEmpty))
                                .zappFont(.body, style: ZappColors.textMuted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 24)
                        }

                        ForEach(store.entries) { entry in
                            row(entry)
                            ZappRowDivider(inset: false)
                        }
                    }
                    .padding(18)
                    .padding(.bottom, 40)
                }

                ZappBottomActionBar(onBack: { store.send(.backTapped) })
            }
            .applyScreenBackground()
            .onAppear { store.send(.onAppear) }
        }
    }

    @ViewBuilder
    private var accountSummary: some View {
        if let account = store.account {
            VStack(alignment: .leading, spacing: 12) {
                ZappBorderedCard {
                    ZappSummaryRow(
                        label: String(localizable: .p2pActivityBaseAddress),
                        value: account.address
                    )
                    ZappButton(
                        title: store.isAddressCopied
                            ? String(localizable: .newChatCopied)
                            : String(localizable: .offrampAccountCopy),
                        variant: .ghost
                    ) { store.send(.copyAddressTapped) }
                }

                ZappBorderedCard {
                    ZappSummaryRow(
                        label: String(localizable: .offrampHistoryBalance),
                        value: account.balanceDisplay.map { String(localizable: .peerUsdcAmount($0)) } ?? "—"
                    )

                    if store.offersRefund {
                        ZappButton(title: String(localizable: .offrampHistoryRefund), variant: .ghost) {
                            store.send(.refundTapped)
                        }
                    } else if store.isRefundBlockedByPeer {
                        // A refund and a cash-out that has not escrowed yet would spend the same
                        // coins, so the button is withheld with the reason rather than failing later.
                        Text(String(localizable: .p2pActivityRefundBlockedByPeer))
                            .zappFont(.caption, style: ZappColors.textMuted)
                    }
                }
            }
        } else if store.isLoading {
            ProgressView()
                .tint(ZappColors.accent.color(colorScheme))
                .frame(maxWidth: .infinity)
        } else {
            Text(String(localizable: .offrampHistoryBalanceUnavailable))
                .zappFont(.caption, style: ZappColors.textMuted)
        }
    }

    @ViewBuilder
    private func row(_ entry: P2pActivityEntry) -> some View {
        switch entry {
        case let .peerAttempt(run):
            entryRow(
                title: String(localizable: .peerUsdcAmount(run.amount.display)),
                subtitle: PeerDestination.displayName(for: run.destinationCode),
                status: String(localizable: .p2pActivityAttemptInProgress),
                statusVariant: .accent,
                date: run.startedAt
            ) { store.send(.entryTapped(entry)) }

        case let .peerOrder(order):
            entryRow(
                title: String(localizable: .peerUsdcAmount(order.gross.display)),
                subtitle: order.destinationCode.map(PeerDestination.displayName(for:))
                    ?? String(localizable: .p2pActivityFilterPeer),
                status: order.phase.label,
                statusVariant: order.isFinished ? .muted : .accent,
                date: order.lastActivityAt ?? order.openedAt
            ) { store.send(.entryTapped(entry)) }

        case let .scanAndPay(item):
            entryRow(
                title: "\(item.fiatDisplay) \(item.currencyCode)",
                subtitle: item.type?.label ?? String(localizable: .p2pActivityFilterScanAndPay),
                status: item.status.capitalized,
                statusVariant: .muted,
                date: item.completedAt ?? item.cancelledAt ?? item.placedAt,
                actionTitle: item.canRecoverEscrow ? String(localizable: .p2pActivityRecover) : nil
            ) { store.send(.entryTapped(entry)) }
        }
    }

    private func entryRow(
        title: String,
        subtitle: String,
        status: String,
        statusVariant: ZappChipVariant,
        date: Date?,
        actionTitle: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).zappFont(.rowTitle, style: ZappColors.text)
                    Text(subtitle).zappFont(.caption, style: ZappColors.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ZappStatusChip(text: status, variant: statusVariant)
            }

            if let date {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .zappFont(.caption, style: ZappColors.textSubtle)
            }

            if let actionTitle {
                ZappButton(title: actionTitle, variant: .ghost, action: action)
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }

    private var selectedFilterIndex: Int {
        P2pActivity.State.Filter.allCases.firstIndex(of: store.filter) ?? 0
    }
}

private extension OfframpHistoryModel {
    /// The subgraph reports fiat in the currency's own 6-decimal unit, the same as USDC.
    var fiatDisplay: String { UsdcAmount(micros: fiatMicros)?.display ?? fiatMicros }
}

#Preview {
    P2pActivityView(store: Store(initialState: P2pActivity.State.initial) { P2pActivity() })
        .applyScreenBackground()
}
