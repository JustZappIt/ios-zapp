// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import SwiftUI
@preconcurrency import ZcashLightClientKit

enum BalanceChartState: Equatable {
    struct FiatData: Equatable {
        let currency: CurrencyISO4217
        let points: [ZappChartPoint]
        let absoluteChange: Decimal
        let percentageChange: Decimal
        let availableFrom: Date
        let dataAsOf: Date
        let isStale: Bool
    }

    case hidden
    case loading
    case data(FiatData)
    case zecData([ZappChartPoint])
    case empty

    /// Whether the chart currently draws something a reload would be throwing away.
    var isRenderable: Bool {
        switch self {
        case .data, .zecData, .empty: return true
        case .hidden, .loading: return false
        }
    }
}

/// Why the Pay chart is not on screen. The chart removing itself is indistinguishable from the
/// chart being broken, so every exit names itself in the log rather than vanishing quietly.
enum BalanceChartHiddenReason: String {
    case historyInconsistent
    case noConfirmedBalance
    case noPositiveBalancePoint
    case priceSeriesUnavailable
    case mappingUnavailable
}

struct ZappBalanceChart: View {
    private struct TaskID: Equatable {
        let period: ZappBalanceChartPeriod
        let currencyCode: String
        let preference: Bool
        let confirmedBalance: Int64
        let transactionRevision: Int
        /// The price window is keyed to the last completed UTC day, so it has to be part of the
        /// identity — otherwise a session that spans midnight keeps drawing yesterday's range.
        let completedPriceDay: Date
        /// Reading `scenePhase` is what makes the body re-evaluate on the way back from the
        /// background, which is when the day above gets re-read. A session left in the FOREGROUND
        /// across midnight is deliberately not covered; that would need a timer for a stale window
        /// no one is looking at.
        let isActive: Bool
    }

    private struct ReconciledHistory {
        let revision: Int
        let history: ZappBalanceHistory
    }

    @Environment(\.colorScheme)
    private var colorScheme
    @Environment(\.scenePhase)
    private var scenePhase
    @Dependency(\.date)
    private var date
    @Dependency(\.historicalPrice)
    private var historicalPrice
    @Dependency(\.userStoredPreferences)
    private var userStoredPreferences

    /// Read through `@Shared` rather than the dependency alone: the setup screen writes the same
    /// `UserDefaults` key, and only an observed read redraws the chart when the user saves the
    /// toggle. Android gets this from `IsPortfolioChartEnabledProvider.observe()`.
    @Shared(.appStorage(UserPreferencesStorage.Constants.ups_portfolioChartEnabled.rawValue))
    private var portfolioChartEnabled = true

    @State private var period = ZappBalanceChartPeriod.week
    @State private var state = BalanceChartState.loading
    @State private var reconciled: ReconciledHistory?
    @State private var formatters = ZappBalanceChartFormatters()
    #if DEBUG
    @State private var hiddenDiagnostic: String?
    #endif

    let transactions: [TransactionState]
    let confirmedBalance: Zatoshi
    let tokenName: String

    var body: some View {
        Group {
            switch state {
            case .hidden:
                #if DEBUG
                // A chart that removes itself looks identical to a chart that is broken. Internal
                // builds say which of the five exits was taken; release builds stay silent.
                hiddenDiagnosticView
                #else
                EmptyView()
                #endif
            case .loading:
                content { loadingChart }
            case .data(let data):
                content {
                    fiatDelta(data)
                    ZappSparkChart(
                        points: data.points,
                        accessibilitySummary: chartAccessibilitySummary(
                            period: period.label,
                            detail: "\(formatCurrency(data.absoluteChange, currency: data.currency)), \(formatPercentage(data.percentageChange))"
                        ),
                        selectionFormatter: { fiatSelection(for: $0, currency: data.currency) }
                    )
                }
            case .zecData(let points):
                content {
                    zecDelta(points)
                    ZappSparkChart(
                        points: points,
                        accessibilitySummary: chartAccessibilitySummary(period: period.label, detail: tokenName),
                        selectionFormatter: zecSelection
                    )
                }
            case .empty:
                content { emptyChart }
            }
        }
        .task(id: taskID) {
            await loadState()
        }
    }

    private func content<Content: View>(@ViewBuilder chart: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localizable: .zappPayChartTitle))
                .zappFont(.sectionTitle, style: ZappColors.text)

            chart()

            // The selector stays mounted in every visible state. Dropping it while a period loaded
            // collapsed the card and pulled the tapped chip out from under the finger.
            ZappChartPeriodSelector(
                options: ZappBalanceChartPeriod.allCases.map(\.label),
                selectedIndex: period.rawValue,
                onSelect: { period = ZappBalanceChartPeriod(rawValue: $0) ?? .week }
            )
        }
    }

    #if DEBUG
    @ViewBuilder private var hiddenDiagnosticView: some View {
        if let hiddenDiagnostic {
            Text(verbatim: hiddenDiagnostic)
                .zappFont(.caption, style: ZappColors.danger)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
        }
    }
    #endif

    private var loadingChart: some View {
        Rectangle()
            .fill(ZappColors.surfaceAlt.color(colorScheme))
            .frame(height: 140)
            .accessibilityHidden(true)
    }

    private var emptyChart: some View {
        Text(String(localizable: .zappPayChartEmpty))
            .zappFont(.caption, style: ZappColors.textSubtle)
            .frame(maxWidth: .infinity, minHeight: 140)
            .multilineTextAlignment(.center)
    }

    private func fiatDelta(_ data: BalanceChartState.FiatData) -> some View {
        let isPositive = data.absoluteChange >= 0
        let style = isPositive ? ZappColors.success : ZappColors.danger
        return HStack(spacing: 8) {
            Text("\(isPositive ? "▲" : "▼") \(formatCurrency(abs(data.absoluteChange), currency: data.currency))")
                .zappFont(.caption, style: style)
            separatorDot
            Text("\(isPositive ? "+" : "-")\(formatPercentage(abs(data.percentageChange)))")
                .zappFont(.caption, style: style)
        }
    }

    @ViewBuilder
    private func zecDelta(_ points: [ZappChartPoint]) -> some View {
        let first = Int64(points.first?.value ?? 0)
        let last = Int64(points.last?.value ?? 0)
        let change = last - first
        let isPositive = change >= 0
        let style = isPositive ? ZappColors.success : ZappColors.danger

        // Android's `computeDelta()` returns null when the window opens on a zero balance — there is
        // no baseline to take a percentage against — and renders no delta row at all.
        if first > 0 {
            HStack(spacing: 8) {
                Text("\(isPositive ? "▲" : "▼") \(Zatoshi(abs(change)).decimalString()) \(tokenName)")
                    .zappFont(.caption, style: style)
                separatorDot
                Text("\(isPositive ? "+" : "-")\(String(format: "%.2f%%", Double(abs(change)) / Double(first) * 100))")
                    .zappFont(.caption, style: style)
            }
        }
    }

    private var separatorDot: some View {
        Rectangle()
            .fill(ZappColors.textSubtle.color(colorScheme))
            .frame(width: 3, height: 3)
    }

    private func fiatSelection(for point: ZappChartPoint, currency: CurrencyISO4217) -> ZappSparkChartSelection {
        selectionReadout(primary: formatCurrency(Decimal(point.value), currency: currency), point: point)
    }

    private func zecSelection(for point: ZappChartPoint) -> ZappSparkChartSelection {
        selectionReadout(primary: "\(Zatoshi(Int64(point.value)).decimalString()) \(tokenName)", point: point)
    }

    private func selectionReadout(primary: String, point: ZappChartPoint) -> ZappSparkChartSelection {
        let day = formatters.day.string(from: point.timestamp)
        return ZappSparkChartSelection(
            primary: primary,
            secondary: day,
            accessibilityDescription: String(localizable: .zappPayChartSelectionAccessibility(primary, day))
        )
    }

    private func chartAccessibilitySummary(period: String, detail: String) -> String {
        String(localizable: .zappPayChartAccessibility(period, detail))
    }

    @MainActor
    private func loadState() async {
        // `isActive` is part of the task identity so returning to the foreground re-reads the
        // clock — but that identity also changes on the way DOWN, and the repository's refresh is
        // an unstructured task that cancellation does not reach. Without this guard, backgrounding
        // would kick off a fetch that outlives the backgrounding that started it.
        guard scenePhase == .active else { return }

        let history = balanceHistory()
        guard case .reconciled(let points, let balance) = history else {
            hide(.historyInconsistent)
            return
        }
        guard balance.amount > 0 else {
            hide(.noConfirmedBalance)
            return
        }
        guard points.contains(where: { $0.balance.amount > 0 }) else {
            hide(.noPositiveBalancePoint)
            return
        }

        guard portfolioChartEnabled else {
            let chartPoints = zecChartPoints(balanceHistory: history, period: period, now: date.now()) ?? []
            state = chartPoints.count >= 2 ? .zecData(chartPoints) : .empty
            return
        }

        // No forced `.loading` here. A cached range resolves on the next actor hop, so blanking the
        // chart first made every period tap flash the placeholder; Android leaves the previous
        // emission on screen until the new one arrives.
        let now = date.now()
        let completedDate = latestCompletedUtcDate(now: now)
        let initialRange = standardizedPriceRange(period: period, completedDate: completedDate)
        guard let initialSeries = await consumePrices(range: initialRange, currency: selectedCurrency, history: history, now: now) else {
            return
        }

        if period == .all {
            let fullRange = standardizedPriceRange(period: period, completedDate: completedDate, availableFrom: initialSeries.availableFrom)
            if fullRange != initialRange {
                _ = await consumePrices(range: fullRange, currency: selectedCurrency, history: history, now: now)
            }
        }
    }

    @MainActor
    private func consumePrices(
        range: PriceDateRange,
        currency: CurrencyISO4217,
        history: ZappBalanceHistory,
        now: Date
    ) async -> DailyPriceSeries? {
        var latestSeries: DailyPriceSeries?
        for await priceState in historicalPrice.states(range, currency) {
            guard !Task.isCancelled else { return nil }
            switch priceState {
            case .loading:
                // Only the very first load shows the placeholder; a reload keeps what is drawn.
                if latestSeries == nil, !state.isRenderable { state = .loading }
            case .unavailable:
                if latestSeries == nil { hide(.priceSeriesUnavailable) }
            case let .data(series, isStale):
                latestSeries = series
                switch mapPortfolioHistory(balanceHistory: history, priceSeries: series, now: now) {
                case .empty:
                    state = .empty
                case .unavailable:
                    hide(.mappingUnavailable)
                case .data(let mapped):
                    state = .data(
                        .init(
                            currency: currency,
                            points: mapped.points,
                            absoluteChange: mapped.absoluteChangeFiat,
                            percentageChange: mapped.percentageChange,
                            availableFrom: series.availableFrom,
                            dataAsOf: series.dataAsOf,
                            isStale: isStale
                        )
                    )
                }
            }
        }
        return latestSeries
    }

    @MainActor
    private func hide(_ reason: BalanceChartHiddenReason) {
        state = .hidden
        LoggerProxy.warn("[ZappBalanceChart] hidden — \(reason.rawValue)")

        #if DEBUG
        // Settled activity has to add up to the confirmed balance exactly, and the gap says which
        // side is wrong. This stays ON SCREEN and nowhere else: `walletLogs` is exportable from
        // Support (`ExportLogsStore`), internal builds run real wallets, and a balance must not
        // survive into a file someone can attach to a ticket. The log line above names the reason,
        // which is all a support thread needs.
        let settled = transactions.filter(\.isSettledForBalanceHistoryDiagnostic)
        let sum = settled.reduce(Int64(0)) { $0 + $1.zecAmount.amount }
        let undated = settled.filter { $0.timestamp == nil }.count
        hiddenDiagnostic = """
            chart hidden: \(reason.rawValue)
            settled \(settled.count)/\(transactions.count), undated \(undated)
            sum \(sum) vs confirmed \(confirmedBalance.amount)
            gap \(confirmedBalance.amount - sum)
            """
        #endif
    }

    /// Reconciliation walks the whole transaction list, so it is memoised: a period tap changes the
    /// window the chart draws, never the history behind it.
    @MainActor
    private func balanceHistory() -> ZappBalanceHistory {
        let revision = transactionRevision
        if let reconciled, reconciled.revision == revision {
            return reconciled.history
        }
        let history = reconcileBalanceHistory(transactions: transactions, confirmedBalance: confirmedBalance)
        reconciled = ReconciledHistory(revision: revision, history: history)
        return history
    }

    private var selectedCurrency: CurrencyISO4217 {
        userStoredPreferences.exchangeRate()?.currency ?? .usd
    }

    private var transactionRevision: Int {
        var hasher = Hasher()
        hasher.combine(confirmedBalance.amount)
        transactions.forEach {
            hasher.combine($0.id)
            hasher.combine($0.timestamp)
            hasher.combine($0.zecAmount.amount)
            hasher.combine($0.balanceHistoryStatusCode)
        }
        return hasher.finalize()
    }

    private var taskID: TaskID {
        TaskID(
            period: period,
            currencyCode: selectedCurrency.code,
            preference: portfolioChartEnabled,
            confirmedBalance: confirmedBalance.amount,
            transactionRevision: transactionRevision,
            completedPriceDay: latestCompletedUtcDate(now: date.now()),
            isActive: scenePhase == .active
        )
    }

    private func formatCurrency(_ value: Decimal, currency: CurrencyISO4217) -> String {
        formatters.currency(currency).string(from: NSDecimalNumber(decimal: value)) ?? ""
    }

    private func formatPercentage(_ value: Decimal) -> String {
        formatters.percentage.string(from: NSDecimalNumber(decimal: value)) ?? ""
    }
}

/// Formatters live here rather than at their call sites because the scrub readout is rebuilt on every
/// canvas frame, and a `DateFormatter` costs more to build than the frame it would be drawn in.
private final class ZappBalanceChartFormatters {
    let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    let percentage: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.multiplier = 1
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private var currencyFormatters: [String: NumberFormatter] = [:]

    func currency(_ currency: CurrencyISO4217) -> NumberFormatter {
        if let existing = currencyFormatters[currency.code] {
            return existing
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.code
        formatter.maximumFractionDigits = currency == .jpy || currency == .krw ? 0 : 2
        currencyFormatters[currency.code] = formatter
        return formatter
    }
}

extension TransactionState {
    #if DEBUG
    /// Mirrors `isSettledForBalanceHistory`, which is fileprivate to the reconciler.
    var isSettledForBalanceHistoryDiagnostic: Bool {
        switch status {
        case .paid, .received, .shielded: return true
        case .failed, .receiving, .sending, .shielding: return false
        }
    }
    #endif

    var balanceHistoryStatusCode: Int {
        switch status {
        case .failed: return 0
        case .paid: return 1
        case .received: return 2
        case .receiving: return 3
        case .sending: return 4
        case .shielding: return 5
        case .shielded: return 6
        }
    }
}
