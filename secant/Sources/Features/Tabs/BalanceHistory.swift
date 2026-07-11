//
//  BalanceHistory.swift
//  Zapp
//
//  Zapp fork: iOS analog of android-zapp's `GetBalanceHistoryUseCase` +
//  `BalanceChartVM` windowing. Builds a running signed-delta balance series
//  from the wallet's transaction list - no backend involved - and windows it
//  to the selected chart period.
//

import Foundation
@preconcurrency import ZcashLightClientKit

struct BalanceHistoryPoint: Equatable {
    let timestamp: TimeInterval
    let balance: Zatoshi
}

enum BalanceChartPeriod: CaseIterable, Equatable {
    case hours24
    case week1
    case month1
    case all

    static let `default` = BalanceChartPeriod.week1

    var window: TimeInterval? {
        switch self {
        case .hours24: return 24 * 60 * 60
        case .week1: return 7 * 24 * 60 * 60
        case .month1: return 30 * 24 * 60 * 60
        case .all: return nil
        }
    }

    var label: String {
        switch self {
        case .hours24: return String(localizable: .zappChartPeriod24h)
        case .week1: return String(localizable: .zappChartPeriod1w)
        case .month1: return String(localizable: .zappChartPeriod1m)
        case .all: return String(localizable: .zappChartPeriodAll)
        }
    }
}

enum BalanceHistory {
    static let minPointsForChart = 2

    /// Running confirmed-balance series over all settled transactions, oldest first.
    /// Mirrors Android: only settled sends/receives move the balance; pending and
    /// failed transactions never settled, and shieldings move funds within the
    /// wallet (no net change).
    static func build(from transactions: [TransactionState]) -> [BalanceHistoryPoint] {
        let ordered = transactions
            .compactMap { tx -> (TimeInterval, TransactionState)? in
                guard let timestamp = tx.timestamp else { return nil }
                return (timestamp, tx)
            }
            .sorted { $0.0 < $1.0 }

        guard !ordered.isEmpty else { return [] }

        var points: [BalanceHistoryPoint] = []
        points.reserveCapacity(ordered.count)
        var running: Int64 = 0
        for (timestamp, tx) in ordered {
            running += signedDelta(tx)
            points.append(
                BalanceHistoryPoint(timestamp: timestamp, balance: Zatoshi(max(running, 0)))
            )
        }
        return points
    }

    /// Windows the full history to the selected period, carrying the last
    /// pre-window balance in as a baseline point and extending the series to
    /// now so a flat balance still draws to the right edge.
    static func window(
        _ history: [BalanceHistoryPoint],
        period: BalanceChartPeriod,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> [BalanceHistoryPoint] {
        guard let window = period.window else { return extendToNow(history, now: now) }

        let cutoff = now - window
        let inWindow = history.filter { $0.timestamp >= cutoff }
        let lastBefore = history.last { $0.timestamp < cutoff }

        var withBaseline = inWindow
        if let lastBefore {
            withBaseline = [BalanceHistoryPoint(timestamp: cutoff, balance: lastBefore.balance)] + inWindow
        }

        guard !withBaseline.isEmpty else { return [] }
        return extendToNow(withBaseline, now: now)
    }

    static func chartData(_ points: [BalanceHistoryPoint]) -> ZappSparkChartData {
        ZappSparkChartData(
            points: points.map {
                ZappSparkChartData.Point(x: $0.timestamp, y: Double($0.balance.amount))
            }
        )
    }

    private static func extendToNow(
        _ points: [BalanceHistoryPoint],
        now: TimeInterval
    ) -> [BalanceHistoryPoint] {
        guard let last = points.last, last.timestamp < now else { return points }
        return points + [BalanceHistoryPoint(timestamp: now, balance: last.balance)]
    }

    private static func signedDelta(_ tx: TransactionState) -> Int64 {
        switch tx.status {
        case .received:
            return tx.zecAmount.amount
        case .paid:
            return -tx.zecAmount.amount
        case .failed, .receiving, .sending, .shielding, .shielded:
            return 0
        }
    }
}
