// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import SwiftUI

struct P2pActivityView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<P2pActivity>

    @State private var isInfoPresented = false

    private enum Layout {
        static let gutter: CGFloat = 14
        static let cardSpacing: CGFloat = 12
        static let logoHeight: CGFloat = 12
        static let logoOpacity: Double = 0.7
    }

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: String(localizable: .p2pActivityTitle)) {
                    ZappInfoButton(
                        accessibilityLabel: String(localizable: .p2pPaymentMethodInfoAccessibility)
                    ) { isInfoPresented = true }
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Layout.cardSpacing) {
                        balanceCard

                        if store.showsFilters {
                            ZappSegmentedSelector(
                                options: P2pActivity.State.Filter.allCases.map(\.label),
                                logos: filterLogos,
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
            .sheet(isPresented: $isInfoPresented) { infoSheet }
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

                    Text(account.balanceDisplay.map { String(localizable: .peerUsdcAmount($0)) } ?? "—")
                        .zappFont(.displaySecondary, style: ZappColors.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if store.offersRefund {
                        ZappCompactButton(
                            title: String(localizable: .offrampHistoryRefund),
                            variant: .primary
                        ) {
                            store.send(.refundTapped)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                    }

                    if let notice = refundNotice {
                        Text(notice)
                            .zappFont(.caption, style: ZappColors.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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

    /// The account lives behind the header rather than in the card: it is reference material, not
    /// something read on every visit.
    private var infoSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localizable: .p2pPaymentMethodInfoTitle))
                .zappFont(.sectionTitle, style: ZappColors.text)

            if let address = store.account?.address {
                ZappBorderedCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localizable: .p2pPaymentMethodInfoBaseLabel))
                            .zappFont(.caption, style: ZappColors.textMuted)

                        HStack(spacing: 8) {
                            Text(address)
                                .zappFont(.mono, style: ZappColors.text)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            ZappCopyIconButton(
                                isCopied: store.isAddressCopied,
                                accessibilityLabel: String(localizable: .offrampAccountCopy)
                            ) {
                                store.send(.copyAddressTapped)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .zappInfoSheet { isInfoPresented = false }
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
            return EntryPresentation(
                providerLogo: Asset.Assets.Icons.providerPeer.image,
                logo: PeerDestination.logo(for: run.destinationCode),
                type: PeerDestination.displayName(for: run.destinationCode),
                status: run.failure == nil
                    ? String(localizable: .p2pActivityAttemptInProgress)
                    : String(localizable: .peerProgressTitleFailed),
                statusVariant: run.failure == nil ? .accent : .danger,
                amount: String(localizable: .peerUsdcAmount(run.amount.display)),
                secondary: run.currencyCodes.joined(separator: ", "),
                date: run.startedAt
            )

        case let .peerOrder(order):
            return EntryPresentation(
                providerLogo: Asset.Assets.Icons.providerPeer.image,
                logo: order.destinationCode.flatMap(PeerDestination.logo(for:)),
                type: order.destinationCode.map(PeerDestination.displayName(for:))
                    ?? String(localizable: .p2pProviderPeer),
                status: order.phase.label,
                statusVariant: order.isFinished ? .muted : .accent,
                amount: String(localizable: .peerUsdcAmount(order.gross.display)),
                secondary: order.currencyCodes.joined(separator: ", "),
                date: order.lastActivityAt ?? order.openedAt
            )

        case let .scanAndPay(item):
            return EntryPresentation(
                providerLogo: Asset.Assets.Icons.providerP2pMe.image,
                logo: nil,
                type: item.type?.label ?? String(localizable: .p2pActivityFilterScanAndPay),
                status: item.status.capitalized,
                statusVariant: .muted,
                amount: String(localizable: .peerUsdcAmount(item.usdcDisplay)),
                secondary: "\(item.fiatDisplay) \(item.currencyCode)",
                date: item.completedAt ?? item.cancelledAt ?? item.placedAt,
                isTappable: false
            )
        }
    }

    @ViewBuilder
    private func entryCard(_ entry: P2pActivityEntry) -> some View {
        let model = presentation(for: entry)
        let content = ZappBorderedCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(Array([model.providerLogo, model.logo].compactMap { $0 }.enumerated()), id: \.offset) { _, mark in
                        mark
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

    /// The provider segments carry their mark; "All" has none and keeps its label.
    private var filterLogos: [Int: Image] {
        var marks: [Int: Image] = [:]
        for (index, filter) in P2pActivity.State.Filter.allCases.enumerated() {
            switch filter {
            case .all: continue
            case .peer: marks[index] = Asset.Assets.Icons.providerPeer.image
            case .scanAndPay: marks[index] = Asset.Assets.Icons.providerP2pMe.image
            }
        }
        return marks
    }
}

/// One row's rendering, so the card builder takes a model rather than nine arguments.
private struct EntryPresentation {
    /// The provider first, then the rail it settled on: a Revolut mark alone does not say which
    /// product opened the order.
    let providerLogo: Image?
    let logo: Image?
    let type: String
    let status: String
    let statusVariant: ZappChipVariant
    let amount: String
    var secondary: String?
    var date: Date?
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
