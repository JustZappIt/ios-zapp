// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import SwiftUI

struct P2pActivityView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<P2pActivity>

    private enum Layout {
        static let gutter: CGFloat = 14
        static let cardSpacing: CGFloat = 12
        static let logoHeight: CGFloat = 12
        static let logoOpacity: Double = 0.7
    }

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: String(localizable: .p2pActivityTitle))

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Layout.cardSpacing) {
                        balanceCard

                        if store.showsFilters {
                            ZappSegmentedSelector(
                                options: P2pActivity.State.Filter.allCases.map(\.label),
                                selectedIndex: selectedFilterIndex
                            ) { index in
                                store.send(.filterTapped(P2pActivity.State.Filter.allCases[index]))
                            }
                        }

                        if let error = store.errorMessage {
                            Text(error)
                                .zappFont(.body, style: ZappColors.danger)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if store.showsEmptyHistory {
                            Text(String(localizable: .p2pActivityEmpty))
                                .zappFont(.body, style: ZappColors.textMuted)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 32)
                        }

                        ForEach(store.entries) { entry in
                            entryCard(entry)
                        }
                    }
                    .padding(.horizontal, Layout.gutter)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }

                ZappBottomActionBar(onBack: { store.send(.backTapped) })
            }
            .applyScreenBackground()
            .onAppear { store.send(.onAppear) }
            .onDisappear { store.send(.onDisappear) }
        }
    }

    /// Balance, the refund control and the account in one card, as `BalanceCard` has it on Android.
    @ViewBuilder
    private var balanceCard: some View {
        if let account = store.account {
            ZappBorderedCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localizable: .offrampHistoryBalance))
                        .zappFont(.eyebrow, style: ZappColors.textMuted)

                    HStack(alignment: .center, spacing: 12) {
                        Text(account.balanceDisplay.map { String(localizable: .peerUsdcAmount($0)) } ?? "—")
                            .zappFont(.display, style: ZappColors.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if store.offersRefund {
                            ZappCompactButton(title: String(localizable: .offrampHistoryRefund)) {
                                store.send(.refundTapped)
                            }
                        }
                    }

                    if let notice = refundNotice {
                        Text(notice)
                            .zappFont(.caption, style: ZappColors.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    accountRow(account.address)
                }
            }
        } else {
            ZappBorderedCard {
                if store.isLoading {
                    ProgressView()
                        .tint(ZappColors.accent.color(colorScheme))
                        .frame(maxWidth: .infinity)
                } else {
                    // An unreadable account is said out loud. Dropping the card takes the address
                    // and the refund control off screen with nothing explaining their absence.
                    Text(String(localizable: .offrampHistoryBalanceUnavailable))
                        .zappFont(.body, style: ZappColors.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func accountRow(_ address: String) -> some View {
        HStack(spacing: 8) {
            Text(String(localizable: .p2pActivityBaseAddress))
                .zappFont(.caption, style: ZappColors.textSubtle)

            Spacer(minLength: 8)

            Text(address)
                .zappFont(.mono, style: ZappColors.text)
                .lineLimit(1)
                .truncationMode(.middle)

            ZappCopyIconButton(
                isCopied: store.isAddressCopied,
                accessibilityLabel: String(localizable: .offrampAccountCopy)
            ) {
                store.send(.copyAddressTapped)
            }
        }
    }

    /// Why the refund is not on offer, when the balance itself is readable.
    private var refundNotice: String? {
        if store.isRefundBlockedByPeer { return String(localizable: .p2pActivityRefundBlockedByPeer) }
        if store.isRefundReadinessUnavailable { return String(localizable: .offrampHistoryBalanceUnavailable) }
        return nil
    }

    private func presentation(for entry: P2pActivityEntry) -> EntryPresentation {
        switch entry {
        case let .peerAttempt(run):
            let rail = PeerDestination.displayName(for: run.destinationCode)
            return EntryPresentation(
                logo: PeerDestination.logo(for: run.destinationCode),
                type: "\(String(localizable: .p2pActivityFilterPeer)) · \(rail)",
                status: run.failure == nil
                    ? String(localizable: .p2pActivityAttemptInProgress)
                    : String(localizable: .peerProgressTitleFailed),
                statusVariant: run.failure == nil ? .accent : .danger,
                amount: String(localizable: .peerUsdcAmount(run.amount.display)),
                secondary: run.currencyCodes.joined(separator: ", "),
                date: run.startedAt
            )

        case let .peerOrder(order):
            let rail = order.destinationCode.map(PeerDestination.displayName(for:))
            return EntryPresentation(
                logo: order.destinationCode.flatMap(PeerDestination.logo(for:)),
                type: rail.map { "\(String(localizable: .p2pActivityFilterPeer)) · \($0)" }
                    ?? String(localizable: .p2pActivityFilterPeer),
                status: order.phase.label,
                statusVariant: order.isFinished ? .muted : .accent,
                amount: String(localizable: .peerUsdcAmount(order.gross.display)),
                secondary: order.currencyCodes.joined(separator: ", "),
                date: order.lastActivityAt ?? order.openedAt
            )

        case let .scanAndPay(item):
            // Recovering an escrow sweeps the Base account, so it is withheld under the same
            // conditions as a refund rather than offered and refused on the next screen.
            let canRecover = item.canRecoverEscrow && store.offersEscrowRecovery
            return EntryPresentation(
                logo: Asset.Assets.Icons.providerP2pMe.image,
                type: item.type?.label ?? String(localizable: .p2pActivityFilterScanAndPay),
                status: item.status.capitalized,
                statusVariant: .muted,
                amount: String(localizable: .peerUsdcAmount(item.usdcDisplay)),
                secondary: "\(item.fiatDisplay) \(item.currencyCode)",
                date: item.completedAt ?? item.cancelledAt ?? item.placedAt,
                actionTitle: canRecover ? String(localizable: .p2pActivityRecover) : nil,
                isTappable: canRecover
            )
        }
    }

    @ViewBuilder
    private func entryCard(_ entry: P2pActivityEntry) -> some View {
        let model = presentation(for: entry)
        let content = ZappBorderedCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if let logo = model.logo {
                        logo
                            .resizable()
                            .scaledToFit()
                            .frame(height: Layout.logoHeight)
                            .opacity(Layout.logoOpacity)
                    }

                    Text(model.type)
                        .zappFont(.eyebrow, style: ZappColors.textMuted)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ZappStatusChip(text: model.status, variant: model.statusVariant)
                }

                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(model.amount)
                        .zappFont(.sectionTitle, style: ZappColors.text)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let secondary = model.secondary, !secondary.isEmpty {
                        Text(secondary)
                            .zappFont(.body, style: ZappColors.textMuted)
                    }
                }

                if let date = model.date {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .zappFont(.caption, style: ZappColors.textSubtle)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                if let actionTitle = model.actionTitle {
                    Text(actionTitle)
                        .zappFont(.buttonSmall, style: ZappColors.accentText)
                }
            }
        }

        if model.isTappable {
            Button { store.send(.entryTapped(entry)) } label: { content }
                .buttonStyle(.zappPress)
        } else {
            content
        }
    }

    private var selectedFilterIndex: Int {
        P2pActivity.State.Filter.allCases.firstIndex(of: store.filter) ?? 0
    }
}

/// One row's rendering, so the card builder takes a model rather than nine arguments.
private struct EntryPresentation {
    let logo: Image?
    let type: String
    let status: String
    let statusVariant: ZappChipVariant
    let amount: String
    var secondary: String?
    var date: Date?
    var actionTitle: String?
    var isTappable = true
}

private extension OfframpHistoryModel {
    /// The subgraph reports fiat in the currency's own 6-decimal unit, the same as USDC.
    var fiatDisplay: String { UsdcAmount(micros: fiatMicros)?.display ?? fiatMicros }

    var usdcDisplay: String { UsdcAmount(micros: usdcMicros)?.display ?? usdcMicros }
}

#Preview {
    P2pActivityView(store: Store(initialState: P2pActivity.State.initial) { P2pActivity() })
        .applyScreenBackground()
}
