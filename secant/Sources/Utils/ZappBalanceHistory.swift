// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
@preconcurrency import ZcashLightClientKit

enum ZappBalanceHistory: Equatable {
    struct Point: Equatable {
        let timestamp: Date
        let balance: Zatoshi
    }

    case reconciled(points: [Point], confirmedBalance: Zatoshi)
    case inconsistent
}

struct ZappChartPoint: Equatable {
    let timestamp: Date
    let value: Double
}

enum ZappBalanceChartPeriod: Int, CaseIterable, Equatable {
    case week
    case month
    case year
    case all

    var label: String {
        switch self {
        case .week: return String(localizable: .zappPayChartPeriod1w)
        case .month: return String(localizable: .zappPayChartPeriod1m)
        case .year: return String(localizable: .zappPayChartPeriod1y)
        case .all: return String(localizable: .zappPayChartPeriodAll)
        }
    }

    var windowDays: Int? {
        switch self {
        case .week: return 7
        case .month: return 30
        case .year: return 365
        case .all: return nil
        }
    }
}

enum ZappPortfolioMappingResult: Equatable {
    struct Data: Equatable {
        let points: [ZappChartPoint]
        let absoluteChangeFiat: Decimal
        let percentageChange: Decimal
    }

    case data(Data)
    case empty
    case unavailable
}

func reconcileBalanceHistory(
    transactions: [TransactionState],
    confirmedBalance: Zatoshi
) -> ZappBalanceHistory {
    var deltasByTimestamp: [Date: Int64] = [:]

    for transaction in transactions where transaction.isSettledForBalanceHistory {
        guard let delta = transaction.balanceHistoryDelta else { return .inconsistent }
        guard let timestamp = transaction.timestamp else {
            // A settled non-zero delta cannot be placed on the curve, so do not invent a timestamp.
            if delta != 0 { return .inconsistent }
            continue
        }
        guard timestamp.isFinite else { return .inconsistent }
        let date = Date(timeIntervalSince1970: timestamp)
        let (sum, overflow) = (deltasByTimestamp[date] ?? 0).addingReportingOverflow(delta)
        if overflow { return .inconsistent }
        deltasByTimestamp[date] = sum
    }

    var runningBalance: Int64 = 0
    var points: [ZappBalanceHistory.Point] = []
    for (timestamp, delta) in deltasByTimestamp.sorted(by: { $0.key < $1.key }) {
        let (updated, overflow) = runningBalance.addingReportingOverflow(delta)
        guard !overflow, updated >= 0 else { return .inconsistent }
        runningBalance = updated
        points.append(.init(timestamp: timestamp, balance: Zatoshi(runningBalance)))
    }

    guard runningBalance == confirmedBalance.amount else { return .inconsistent }
    return .reconciled(points: points, confirmedBalance: confirmedBalance)
}

func mapPortfolioHistory(
    balanceHistory: ZappBalanceHistory,
    priceSeries: DailyPriceSeries,
    now: Date
) -> ZappPortfolioMappingResult {
    guard case .reconciled(let historyPoints, let confirmedBalance) = balanceHistory else {
        return .unavailable
    }

    let prices = priceSeries.points.sorted { $0.date < $1.date }
    guard prices.count >= 2 else { return .empty }
    for (first, second) in zip(prices, prices.dropFirst()) where second.date != HistoricalPriceDate.addingDays(1, to: first.date) {
        return .unavailable
    }

    let balances = historyPoints.sorted { $0.timestamp < $1.timestamp }
    guard let firstPositive = balances.first(where: { $0.balance.amount > 0 }) else { return .empty }
    let lastPriceExclusive = HistoricalPriceDate.addingDays(1, to: prices[prices.count - 1].date)
    guard firstPositive.timestamp < lastPriceExclusive else { return .unavailable }

    var balanceIndex = 0
    var effectiveBalance: Int64 = 0
    var valued: [(Date, Decimal)] = []
    for price in prices {
        let nextDay = HistoricalPriceDate.addingDays(1, to: price.date)
        while balanceIndex < balances.count, balances[balanceIndex].timestamp < nextDay {
            effectiveBalance = balances[balanceIndex].balance.amount
            balanceIndex += 1
        }
        let zec = Decimal(effectiveBalance) / Decimal(100_000_000)
        let value = zec * price.fiatPerZec
        if value > 0 || !valued.isEmpty {
            valued.append((price.date, value))
        }
    }
    guard valued.count >= 2 else { return .empty }

    let currentZec = Decimal(confirmedBalance.amount) / Decimal(100_000_000)
    let currentValue = currentZec * prices[prices.count - 1].fiatPerZec
    let lastTimestamp = valued[valued.count - 1].0.addingTimeInterval(1)
    valued.append((max(now, lastTimestamp), currentValue))

    let firstValue = valued[0].1
    guard firstValue > 0 else { return .empty }
    let absoluteChange = currentValue - firstValue
    let percentageChange = absoluteChange / firstValue * 100
    return .data(
        .init(
            points: valued.map { .init(timestamp: $0.0, value: NSDecimalNumber(decimal: $0.1).doubleValue) },
            absoluteChangeFiat: absoluteChange,
            percentageChange: percentageChange
        )
    )
}

func latestCompletedUtcDate(now: Date) -> Date {
    let components = HistoricalPriceDate.utcCalendar.dateComponents([.hour, .minute], from: now)
    let isInGrace = components.hour == 0 && (components.minute ?? 0) < 10
    return HistoricalPriceDate.addingDays(isInGrace ? -2 : -1, to: HistoricalPriceDate.startOfDay(now))
}

func standardizedPriceRange(
    period: ZappBalanceChartPeriod,
    completedDate: Date,
    availableFrom: Date? = nil
) -> PriceDateRange {
    let start: Date
    switch period {
    case .week:
        start = HistoricalPriceDate.addingDays(-7, to: completedDate)
    case .month:
        start = HistoricalPriceDate.addingDays(-30, to: completedDate)
    case .year:
        start = HistoricalPriceDate.addingDays(-365, to: completedDate)
    case .all:
        start = availableFrom ?? HistoricalPriceDate.addingDays(-7, to: completedDate)
    }
    return PriceDateRange(from: start, to: completedDate)
}

func zecChartPoints(
    balanceHistory: ZappBalanceHistory,
    period: ZappBalanceChartPeriod,
    now: Date
) -> [ZappChartPoint]? {
    guard case .reconciled(let points, let confirmedBalance) = balanceHistory,
        confirmedBalance.amount > 0,
        points.contains(where: { $0.balance.amount > 0 }) else {
        return nil
    }

    let selected: [ZappBalanceHistory.Point]
    if let days = period.windowDays {
        let cutoff = now.addingTimeInterval(TimeInterval(-days * 24 * 60 * 60))
        var inWindow = points.filter { $0.timestamp >= cutoff }
        if let baseline = points.last(where: { $0.timestamp < cutoff }) {
            inWindow.insert(.init(timestamp: cutoff, balance: baseline.balance), at: 0)
        }
        selected = inWindow
    } else {
        selected = points
    }

    guard let last = selected.last else { return [] }
    let extended = last.timestamp < now ? selected + [.init(timestamp: now, balance: last.balance)] : selected
    return extended.map { .init(timestamp: $0.timestamp, value: Double($0.balance.amount)) }
}

private extension TransactionState {
    var balanceHistoryDelta: Int64? {
        guard zecAmount.amount >= 0 else { return nil }
        return isSentTransaction ? -zecAmount.amount : zecAmount.amount
    }

    var isSettledForBalanceHistory: Bool {
        switch status {
        case .paid, .received, .shielded:
            return true
        case .failed, .receiving, .sending, .shielding:
            return false
        }
    }
}
