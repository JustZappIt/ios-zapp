// SPDX-License-Identifier: MIT OR Apache-2.0

import SwiftUI
@preconcurrency import ZcashLightClientKit

/// Balance history derived from settled wallet activity, matching Android's GetBalanceHistoryUseCase.
struct ZappBalanceChart: View {
    private enum Period: Int, CaseIterable {
        case day
        case week
        case month
        case all

        var label: String {
            switch self {
            case .day: return "24H"
            case .week: return "1W"
            case .month: return "1M"
            case .all: return "ALL"
            }
        }

        var interval: TimeInterval? {
            switch self {
            case .day: return 24 * 60 * 60
            case .week: return 7 * 24 * 60 * 60
            case .month: return 30 * 24 * 60 * 60
            case .all: return nil
            }
        }
    }

    private struct Point: Equatable {
        let date: Date
        let balance: Int64
    }

    @Environment(\.colorScheme) private var colorScheme
    @State private var period = Period.week

    let transactions: [TransactionState]
    let tokenName: String

    var body: some View {
        let points = windowedPoints
        if points.count >= 2 {
            VStack(alignment: .leading, spacing: 14) {
                delta(points)
                sparkline(points)
                    .frame(height: 140)
                ZappSegmentedSelector(
                    options: Period.allCases.map(\.label),
                    selectedIndex: period.rawValue,
                    onSelect: { period = Period(rawValue: $0) ?? .week }
                )
            }
        }
    }

    private func delta(_ points: [Point]) -> some View {
        let first = points.first?.balance ?? 0
        let last = points.last?.balance ?? 0
        let change = last - first
        let isPositive = change >= 0
        // Android's `computeDelta()` returns null when the window opens on a zero balance,
        // because there is no baseline to take a percentage against. It then renders the
        // period label alone rather than a change with no percentage beside it.
        let percent = first > 0 ? Double(abs(change)) / Double(first) * 100 : nil

        return HStack(spacing: 8) {
            if let percent {
                Text("\(isPositive ? "▲" : "▼") \(Zatoshi(abs(change)).decimalString()) \(tokenName)")
                    .zappFont(.caption, style: isPositive ? ZappColors.success : ZappColors.danger)
                separatorDot
                Text("\(isPositive ? "+" : "-")\(String(format: "%.2f%%", percent))")
                    .zappFont(.caption, style: isPositive ? ZappColors.success : ZappColors.danger)
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

    private func sparkline(_ points: [Point]) -> some View {
        Canvas { context, size in
            guard let firstDate = points.first?.date.timeIntervalSince1970,
                  let lastDate = points.last?.date.timeIntervalSince1970 else { return }
            let values = points.map(\.balance)
            let minimum = values.min() ?? 0
            let maximum = values.max() ?? 0
            let dateRange = max(lastDate - firstDate, 1)
            let valueRange = Double(maximum - minimum)
            let lineWidth = 2.0
            let plotHeight = max(size.height - lineWidth * 2, 1)

            let coordinates = points.map { point in
                // Center a flat (zero-range) window instead of pinning it to the baseline.
                let fraction = valueRange > 0 ? Double(point.balance - minimum) / valueRange : 0.5
                return CGPoint(
                    x: (point.date.timeIntervalSince1970 - firstDate) / dateRange * size.width,
                    y: lineWidth + (1 - fraction) * plotHeight
                )
            }
            guard let first = coordinates.first else { return }

            var line = Path()
            line.move(to: first)
            for point in coordinates.dropFirst() { line.addLine(to: point) }

            var area = line
            area.addLine(to: CGPoint(x: coordinates.last?.x ?? size.width, y: size.height))
            area.addLine(to: CGPoint(x: first.x, y: size.height))
            area.closeSubpath()

            let accent = ZappColors.accent.color(colorScheme)
            context.fill(
                area,
                with: .linearGradient(
                    Gradient(colors: [accent.opacity(0.24), accent.opacity(0.02)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )
            context.stroke(line, with: .color(accent), lineWidth: lineWidth)
        }
        .accessibilityHidden(true)
    }

    private var windowedPoints: [Point] {
        let history = balanceHistory
        guard !history.isEmpty else { return [] }
        let now = Date()
        guard let interval = period.interval else { return extendToNow(history, now: now) }
        let cutoff = now.addingTimeInterval(-interval)
        let baseline = history.last { $0.date < cutoff }
        var result = history.filter { $0.date >= cutoff }
        if let baseline {
            result.insert(Point(date: cutoff, balance: baseline.balance), at: 0)
        }
        return extendToNow(result, now: now)
    }

    private var balanceHistory: [Point] {
        let ordered = transactions.compactMap { transaction -> (Date, TransactionState)? in
            guard let timestamp = transaction.timestamp else { return nil }
            return (Date(timeIntervalSince1970: timestamp), transaction)
        }.sorted { $0.0 < $1.0 }

        var running: Int64 = 0
        return ordered.map { date, transaction in
            let delta: Int64
            switch transaction.status {
            case .paid where !transaction.isShieldingTransaction:
                delta = transaction.zecAmount.amount
            case .received:
                delta = transaction.zecAmount.amount
            default:
                delta = 0
            }
            running = max(0, running + delta)
            return Point(date: date, balance: running)
        }
    }

    private func extendToNow(_ points: [Point], now: Date) -> [Point] {
        guard let last = points.last else { return [] }
        guard last.date < now else { return points }
        return points + [Point(date: now, balance: last.balance)]
    }
}
