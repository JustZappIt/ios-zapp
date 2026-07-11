//
//  WalletTabView.swift
//  Zapp
//
//  Zapp fork: iOS analog of android-zapp's `WalletTabContent` +
//  `WalletHomeView` + `WalletBalanceCard` + `WalletSyncStatusViews`. Re-homes
//  ZODL's Home feature as the Pay tab: the upstream Home / WalletBalances /
//  TransactionList / SmartBanner reducers stay untouched - this view is a
//  Zapp-styled front end over their state, routed through the existing
//  `.home(...)` actions.
//

import SwiftUI
import ComposableArchitecture
@preconcurrency import ZcashLightClientKit

// MARK: - Sync status model

/// Android `WalletSyncStatus` / `WalletSyncChipState`.
enum WalletSyncStatus: Equatable {
    case synced
    case syncing
    case restoring
    case disconnected
    case error
    case initializing
}

struct WalletSyncChipState: Equatable {
    let status: WalletSyncStatus
    let progressPercent: Double
}

// MARK: - Wallet tab

struct WalletTabView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<Root>
    let tokenName: String

    @Shared(.inMemory(.walletStatus)) var walletStatus: WalletStatus = .none
    @Shared(.inMemory(.transactions)) var transactions: IdentifiedArrayOf<TransactionState> = []
    @Shared(.inMemory(.exchangeRate)) var currencyConversion: CurrencyConversion? = nil
    @Shared(.inMemory(.swapAssets)) var swapAssets: IdentifiedArrayOf<SwapAsset> = []

    // Android: BalanceChartVM.selectedPeriod / WalletHomeView.showZecAsPrimary,
    // both held as screen state.
    @State private var selectedPeriod: BalanceChartPeriod = .default
    @State private var showZecAsPrimary = false

    private var syncChip: WalletSyncChipState {
        let snapshot = store.homeState.smartBannerState.synchronizerStatusSnapshot
        let known = store.homeState.smartBannerState.lastKnownSyncPercentage
        let percent = known >= 0 ? known * 100 : 0

        let status: WalletSyncStatus
        switch snapshot.syncStatus {
        case .upToDate:
            status = .synced
        case .syncing:
            status = walletStatus == .restoring || walletStatus == .resyncing ? .restoring : .syncing
        case .error:
            status = .error
        case .stopped:
            status = .disconnected
        case .unprepared:
            status = .initializing
        }
        return WalletSyncChipState(status: status, progressPercent: min(max(percent, 0), 100))
    }

    var body: some View {
        WithPerceptionTracking {
            ZStack {
                // Unlike Android's SecretState.LOADING gate, the wallet always
                // exists once `.home` shows on iOS, so the home layout renders
                // immediately; the sync chip carries the connecting state.
                walletHome()

                // Android PayActionSpeedDial. Send / Receive / Scan / Swap route
                // into the existing coord flows via upstream Home actions; the
                // offramp (Pay Merchant) slot is deferred to Phase 3.
                ZappSpeedDialFab(
                    actions: [
                        ZappSpeedDialAction(
                            id: "send",
                            icon: Asset.Assets.Icons.sent.image,
                            label: String(localizable: .tabsSend)
                        ) {
                            store.send(.home(.sendTapped))
                        },
                        ZappSpeedDialAction(
                            id: "receive",
                            icon: Asset.Assets.Icons.received.image,
                            label: String(localizable: .tabsReceive)
                        ) {
                            store.send(.home(.receiveScreenRequested))
                        },
                        ZappSpeedDialAction(
                            id: "scan",
                            icon: Asset.Assets.Icons.scan.image,
                            label: String(localizable: .zappFabScan)
                        ) {
                            store.send(.home(.scanTapped))
                        },
                        ZappSpeedDialAction(
                            id: "swap",
                            icon: Asset.Assets.Icons.swap.image,
                            label: String(localizable: .swapAndPaySwap)
                        ) {
                            store.send(.home(.swapWithNearTapped))
                        }
                    ]
                )
            }
        }
    }
}

// MARK: - Home layout (Android WalletHomeView)

private extension WalletTabView {
    @ViewBuilder func walletHome() -> some View {
        // Android WalletHomeView puts the header and sync row inside the
        // LazyColumn, so they scroll away with the content.
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZappScreenHeader(title: String(localizable: .zappTabPay)) {
                    syncStatusChip(syncChip)
                }

                syncProgressRow(syncChip)

                VStack(alignment: .leading, spacing: 0) {
                    balanceCard()
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                        .padding(.bottom, 20)

                    // Upstream smart banner (backup reminder, shielding, sync
                    // error reporting, currency and Tor setup). Android has no
                    // banner; kept on iOS because these flows have no other
                    // entry point yet - flagged in docs/zapp-phase2-shell.md.
                    SmartBannerView(
                        store: store.scope(
                            state: \.homeState.smartBannerState,
                            action: \.home.smartBanner
                        ),
                        tokenName: tokenName
                    )

                    ZappSectionLabel(text: String(localizable: .zappActivityTitle))
                        .padding(.leading, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 8)

                    activitySection()
                }
                .padding(.bottom, ZappNavBar.clearance)
            }
        }
        .onAppear { store.send(.home(.onAppear)) }
        .onDisappear { store.send(.home(.onDisappear)) }
    }

    // MARK: Sync chip + progress (Android WalletSyncStatusViews)

    @ViewBuilder func syncStatusChip(_ state: WalletSyncChipState) -> some View {
        switch state.status {
        case .synced:
            ZappStatusChip(text: String(localizable: .zappSyncSynced), variant: .success)
        case .syncing:
            ZappStatusChip(
                text: "\(String(localizable: .zappSyncSyncing)) \(formattedPercent(state.progressPercent))",
                variant: .accent
            )
        case .restoring:
            ZappStatusChip(
                text: "\(String(localizable: .zappSyncRestoring)) \(formattedPercent(state.progressPercent))",
                variant: .accent
            )
        case .disconnected:
            ZappStatusChip(text: String(localizable: .zappSyncOffline), variant: .danger)
        case .error:
            ZappStatusChip(text: String(localizable: .zappSyncError), variant: .danger)
        case .initializing:
            ZappStatusChip(text: String(localizable: .zappSyncConnecting), variant: .muted)
        }
    }

    @ViewBuilder func syncProgressRow(_ state: WalletSyncChipState) -> some View {
        if state.status != .synced {
            let isError = state.status == .disconnected || state.status == .error
            let showPercent = state.status == .syncing || state.status == .restoring
            let fillColor = isError ? ZappColor.danger(colorScheme) : ZappColor.accent(colorScheme)

            VStack(spacing: 6) {
                HStack {
                    Text(progressLabel(state.status))
                        .zFont(.semiBold, size: 12, color: isError ? ZappColor.danger(colorScheme) : ZappColor.textMuted(colorScheme))

                    Spacer()

                    if showPercent {
                        Text(formattedPercent(state.progressPercent))
                            .font(.custom(FontFamily.Inter.black.name, size: 12))
                            .foregroundColor(ZappColor.text(colorScheme))
                    }
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(ZappColor.surfaceAlt(colorScheme))

                        if showPercent {
                            Rectangle()
                                .fill(fillColor)
                                .frame(width: proxy.size.width * max(state.progressPercent / 100, 0.02))
                        } else if isError {
                            Rectangle()
                                .fill(fillColor)
                        }
                    }
                }
                .frame(height: 3)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
    }

    func progressLabel(_ status: WalletSyncStatus) -> String {
        switch status {
        case .syncing: return String(localizable: .zappSyncSyncing)
        case .restoring: return String(localizable: .zappSyncRestoring)
        case .initializing: return String(localizable: .zappSyncConnecting)
        case .disconnected: return String(localizable: .zappSyncOfflineReconnecting)
        case .error: return String(localizable: .zappSyncError)
        case .synced: return ""
        }
    }

    func formattedPercent(_ percent: Double) -> String {
        String(format: "%.2f%%", percent)
    }

    // MARK: Balance card (Android WalletBalanceCard)

    @ViewBuilder func balanceCard() -> some View {
        let totalBalance = store.homeState.walletBalancesState.totalBalance
        let history = BalanceHistory.build(from: Array(transactions))
        let windowed = BalanceHistory.window(history, period: selectedPeriod)
        let hasChart = totalBalance.amount > 0 && windowed.count >= BalanceHistory.minPointsForChart

        VStack(alignment: .leading, spacing: 0) {
            ZappSectionLabel(text: String(localizable: .zappBalanceTotalLabel))
                .padding(.bottom, 8)

            balanceHero(totalBalance)

            if hasChart {
                balanceDelta(windowed)
                    .padding(.top, 10)

                ZappSparkChart(data: BalanceHistory.chartData(windowed))
                    .padding(.top, 14)

                ZappSegmentedSelector(
                    options: BalanceChartPeriod.allCases.map(\.label),
                    selectedIndex: BalanceChartPeriod.allCases.firstIndex(of: selectedPeriod) ?? 0,
                    onSelect: { index in
                        selectedPeriod = BalanceChartPeriod.allCases[index]
                    }
                )
                .padding(.top, 14)
            }
        }
    }

    /// Android `zecFiatRate`: prefer the user's exchange-rate currency, fall
    /// back to the always-on USD price from the 1-Click swap asset catalog.
    func formattedFiat(_ balance: Zatoshi) -> (whole: String, fraction: String)? {
        if let conversion = currencyConversion {
            return splitFiat(conversion.convert(balance) as String)
        }
        if let usdPrice = zecUsdPrice, usdPrice > 0 {
            let amount = usdPrice * Decimal(balance.amount) / Decimal(100_000_000)
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = "USD"
            formatter.currencySymbol = "$"
            if let formatted = formatter.string(from: NSDecimalNumber(decimal: amount)) {
                return splitFiat(formatted)
            }
        }
        return nil
    }

    var zecUsdPrice: Decimal? {
        swapAssets.first { $0.token.lowercased() == "zec" }?.usdPrice
    }

    /// Android `formatFiat`: whole part carries the symbol, fraction renders
    /// smaller and muted. Splits on the locale decimal separator.
    func splitFiat(_ formatted: String) -> (whole: String, fraction: String) {
        let separator = Locale.current.decimalSeparator ?? "."
        guard let range = formatted.range(of: separator, options: .backwards) else {
            return (formatted, "")
        }
        return (String(formatted[..<range.lowerBound]), String(formatted[range.lowerBound...]))
    }

    /// Swiss hero: Black weight, oversized, fiat-first with a tap toggle to
    /// ZEC-first - mirroring Android's `BalanceAmount`.
    @ViewBuilder func balanceHero(_ balance: Zatoshi) -> some View {
        let fiat = formattedFiat(balance)

        Button {
            if fiat != nil {
                showZecAsPrimary.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                if let fiat, !showZecAsPrimary {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(fiat.whole)
                            .font(.custom(FontFamily.Inter.black.name, size: 52))
                            .kerning(-3)
                            .foregroundColor(ZappColor.text(colorScheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)

                        Text(fiat.fraction)
                            .font(.custom(FontFamily.Inter.bold.name, size: 26))
                            .kerning(-1)
                            .foregroundColor(ZappColor.textMuted(colorScheme))
                    }

                    HStack(spacing: 4) {
                        ZatoshiText(balance)
                            .zFont(size: 13, color: ZappColor.textMuted(colorScheme))
                        Text(tokenName)
                            .zFont(size: 13, color: ZappColor.textMuted(colorScheme))
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        ZatoshiText(balance)
                            .font(.custom(FontFamily.Inter.black.name, size: 52))
                            .foregroundColor(ZappColor.text(colorScheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)

                        Text(tokenName)
                            .zFont(size: 22, color: ZappColor.textMuted(colorScheme))
                    }

                    if let fiat {
                        Text(fiat.whole + fiat.fraction)
                            .zFont(size: 13, color: ZappColor.textMuted(colorScheme))
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Android `BalanceDelta`: signed period change + percent + period label.
    @ViewBuilder func balanceDelta(_ points: [BalanceHistoryPoint]) -> some View {
        if let first = points.first, let last = points.last, first.balance.amount != 0 {
            let delta = last.balance.amount - first.balance.amount
            let percent = Double(delta) / Double(first.balance.amount) * 100
            let isPositive = delta >= 0
            let color = isPositive ? ZappColor.success(colorScheme) : ZappColor.danger(colorScheme)
            let deltaZec = Zatoshi(abs(delta))

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text(isPositive ? "▲" : "▼")
                        .zFont(size: 12, color: color)
                    ZatoshiText(deltaZec)
                        .zFont(size: 12, color: color)
                    Text(tokenName)
                        .zFont(size: 12, color: color)
                }

                deltaDot()

                Text(String(format: "%@%.2f%%", isPositive ? "+" : "-", abs(percent)))
                    .zFont(size: 12, color: color)

                deltaDot()

                Text(selectedPeriod.label)
                    .zFont(size: 12, color: ZappColor.textMuted(colorScheme))
            }
        } else {
            Text(selectedPeriod.label)
                .zFont(size: 12, color: ZappColor.textMuted(colorScheme))
        }
    }

    @ViewBuilder func deltaDot() -> some View {
        Rectangle()
            .fill(ZappColor.textSubtle(colorScheme))
            .frame(width: 3, height: 3)
    }

    // MARK: Activity (Android WalletActivitySection)

    @ViewBuilder func activitySection() -> some View {
        if store.homeState.transactionListState.transactions.isEmpty
            && !store.homeState.transactionListState.isInvalidated {
            activityEmpty()
        } else {
            VStack(spacing: 0) {
                TransactionListView(
                    store: store.scope(
                        state: \.homeState.transactionListState,
                        action: \.home.transactionList
                    ),
                    tokenName: tokenName,
                    scrollable: false
                )

                if store.homeState.transactionListState.transactions.count > TransactionList.Constants.homePageTransactionsCount {
                    seeAllRow()
                }
            }
        }
    }

    /// Android `ActivityEmpty`: left-aligned Swiss block with a 3pt accent stripe.
    @ViewBuilder func activityEmpty() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(ZappColor.accent(colorScheme))
                .frame(width: 3, height: 20)
                .padding(.bottom, 10)

            Text(localizable: .zappActivityEmptyTitle)
                .font(.custom(FontFamily.Inter.black.name, size: 15))
                .kerning(-0.3)
                .foregroundColor(ZappColor.text(colorScheme))
                .padding(.bottom, 4)

            Text(localizable: .zappActivityEmptySubtitle)
                .zFont(size: 12, color: ZappColor.textMuted(colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
    }

    @ViewBuilder func seeAllRow() -> some View {
        Button {
            store.send(.home(.seeAllTransactionsTapped))
        } label: {
            Text(localizable: .transactionHistorySeeAll)
                .zFont(size: 14, color: ZappColor.accentText(colorScheme))
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
        }
    }
}
