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
}

struct ZappBalanceChart: View {
    private struct TaskID: Equatable {
        let period: ZappBalanceChartPeriod
        let currencyCode: String
        let preference: Bool
        let confirmedBalance: Int64
        let transactionRevision: Int
    }

    @Environment(\.colorScheme)
    private var colorScheme
    @Dependency(\.date)
    private var date
    @Dependency(\.historicalPrice)
    private var historicalPrice
    @Dependency(\.userStoredPreferences)
    private var userStoredPreferences

    @State private var period = ZappBalanceChartPeriod.week
    @State private var state = BalanceChartState.loading

    let transactions: [TransactionState]
    let confirmedBalance: Zatoshi
    let tokenName: String

    var body: some View {
        Group {
            switch state {
            case .hidden:
                EmptyView()
            case .loading:
                content(showsPeriodSelector: false) { loadingChart }
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

    private func content<Content: View>(
        showsPeriodSelector: Bool = true,
        @ViewBuilder chart: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localizable: .zappPayChartTitle))
                .zappFont(.sectionTitle, style: ZappColors.text)

            chart()

            if showsPeriodSelector {
                ZappSegmentedSelector(
                    options: ZappBalanceChartPeriod.allCases.map(\.label),
                    selectedIndex: period.rawValue,
                    onSelect: { period = ZappBalanceChartPeriod(rawValue: $0) ?? .week }
                )
            }
        }
    }

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
            separatorDot
            Text(period.label)
                .zappFont(.caption, style: ZappColors.textMuted)
        }
    }

    private func zecDelta(_ points: [ZappChartPoint]) -> some View {
        let first = Int64(points.first?.value ?? 0)
        let last = Int64(points.last?.value ?? 0)
        let change = last - first
        let isPositive = change >= 0
        let percent = first > 0 ? Double(abs(change)) / Double(first) * 100 : nil
        let style = isPositive ? ZappColors.success : ZappColors.danger

        return HStack(spacing: 8) {
            if let percent {
                Text("\(isPositive ? "▲" : "▼") \(Zatoshi(abs(change)).decimalString()) \(tokenName)")
                    .zappFont(.caption, style: style)
                separatorDot
                Text("\(isPositive ? "+" : "-")\(String(format: "%.2f%%", percent))")
                    .zappFont(.caption, style: style)
                separatorDot
            }
            Text(period.label)
                .zappFont(.caption, style: ZappColors.textMuted)
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
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let day = formatter.string(from: point.timestamp)
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
        let history = reconcileBalanceHistory(transactions: transactions, confirmedBalance: confirmedBalance)
        guard case .reconciled(let points, let balance) = history,
            balance.amount > 0,
            points.contains(where: { $0.balance.amount > 0 }) else {
            state = .hidden
            return
        }

        guard userStoredPreferences.portfolioChartEnabled() else {
            let chartPoints = zecChartPoints(balanceHistory: history, period: period, now: date.now()) ?? []
            state = chartPoints.count >= 2 ? .zecData(chartPoints) : .empty
            return
        }

        state = .loading
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
                if latestSeries == nil { state = .loading }
            case .unavailable:
                if latestSeries == nil { state = .hidden }
            case let .data(series, isStale):
                latestSeries = series
                switch mapPortfolioHistory(balanceHistory: history, priceSeries: series, now: now) {
                case .empty:
                    state = .empty
                case .unavailable:
                    state = .hidden
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

    private var selectedCurrency: CurrencyISO4217 {
        userStoredPreferences.exchangeRate()?.currency ?? .usd
    }

    private var taskID: TaskID {
        var hasher = Hasher()
        transactions.forEach {
            hasher.combine($0.id)
            hasher.combine($0.timestamp)
            hasher.combine($0.zecAmount.amount)
            hasher.combine($0.balanceHistoryStatusCode)
        }
        return TaskID(
            period: period,
            currencyCode: selectedCurrency.code,
            preference: userStoredPreferences.portfolioChartEnabled(),
            confirmedBalance: confirmedBalance.amount,
            transactionRevision: hasher.finalize()
        )
    }

    private func formatCurrency(_ value: Decimal, currency: CurrencyISO4217) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.code
        formatter.maximumFractionDigits = currency == .jpy || currency == .krw ? 0 : 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? ""
    }

    private func formatPercentage(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.multiplier = 1
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? ""
    }
}

private extension TransactionState {
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
