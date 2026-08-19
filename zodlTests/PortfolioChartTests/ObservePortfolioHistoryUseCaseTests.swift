import Foundation
import Testing
@preconcurrency import ZcashLightClientKit
@testable import zodl_internal

@Suite
struct ObservePortfolioHistoryUseCaseTests {
    @Test
    func valuesEachDayAtItsCloseAndAppendsCurrentValue() throws {
        let first = day("2026-08-01")
        let second = day("2026-08-02")
        let now = day("2026-08-03").addingTimeInterval(12 * 60 * 60)
        let history = ZappBalanceHistory.reconciled(
            points: [
                .init(timestamp: first.addingTimeInterval(60), balance: Zatoshi(100_000_000)),
                .init(timestamp: second.addingTimeInterval(60), balance: Zatoshi(200_000_000))
            ],
            confirmedBalance: Zatoshi(200_000_000)
        )
        let series = prices([10, 20], starting: first)

        let result = try #require(data(mapPortfolioHistory(balanceHistory: history, priceSeries: series, now: now)))

        #expect(result.points.map(\.value) == [10, 40, 40])
        #expect(result.absoluteChangeFiat == 30)
        #expect(result.percentageChange == 300)
        #expect(result.points.last?.timestamp == now)
    }

    @Test
    func fewerThanTwoPricesIsEmpty() {
        let first = day("2026-08-01")
        let history = positiveHistory(at: first)
        #expect(mapPortfolioHistory(balanceHistory: history, priceSeries: prices([10], starting: first), now: first) == .empty)
    }

    @Test
    func dailyGapIsUnavailable() {
        let first = day("2026-08-01")
        let series = DailyPriceSeries(
            fiatCurrency: .usd,
            points: [
                .init(date: first, fiatPerZec: 10),
                .init(date: HistoricalPriceDate.addingDays(2, to: first), fiatPerZec: 20)
            ],
            availableFrom: first,
            availableTo: HistoricalPriceDate.addingDays(2, to: first),
            dataAsOf: HistoricalPriceDate.addingDays(2, to: first)
        )
        #expect(mapPortfolioHistory(balanceHistory: positiveHistory(at: first), priceSeries: series, now: first) == .unavailable)
    }

    @Test
    func noPositiveBalanceIsEmpty() {
        let first = day("2026-08-01")
        let history = ZappBalanceHistory.reconciled(
            points: [.init(timestamp: first, balance: .zero)],
            confirmedBalance: .zero
        )
        #expect(mapPortfolioHistory(balanceHistory: history, priceSeries: prices([10, 20], starting: first), now: first) == .empty)
    }

    @Test
    func walletNewerThanPriceRangeIsUnavailable() {
        let first = day("2026-08-01")
        let history = positiveHistory(at: HistoricalPriceDate.addingDays(2, to: first))
        #expect(mapPortfolioHistory(balanceHistory: history, priceSeries: prices([10, 20], starting: first), now: first) == .unavailable)
    }

    @Test
    func completedDateUsesPostMidnightGrace() {
        let midnight = day("2026-08-03")
        #expect(latestCompletedUtcDate(now: midnight.addingTimeInterval(9 * 60)) == day("2026-08-01"))
        #expect(latestCompletedUtcDate(now: midnight.addingTimeInterval(10 * 60)) == day("2026-08-02"))
    }

    private func day(_ value: String) -> Date {
        guard let date = HistoricalPriceDate.parseDay(value) else {
            preconditionFailure("Invalid test date: \(value)")
        }
        return date
    }

    private func positiveHistory(at date: Date) -> ZappBalanceHistory {
        .reconciled(
            points: [.init(timestamp: date.addingTimeInterval(60), balance: Zatoshi(100_000_000))],
            confirmedBalance: Zatoshi(100_000_000)
        )
    }

    private func prices(_ values: [Decimal], starting first: Date) -> DailyPriceSeries {
        let points = values.enumerated().map {
            DailyFiatPrice(date: HistoricalPriceDate.addingDays($0.offset, to: first), fiatPerZec: $0.element)
        }
        return DailyPriceSeries(
            fiatCurrency: .usd,
            points: points,
            availableFrom: first,
            availableTo: points.last?.date ?? first,
            dataAsOf: points.last?.date ?? first
        )
    }

    private func data(_ result: ZappPortfolioMappingResult) -> ZappPortfolioMappingResult.Data? {
        guard case .data(let data) = result else { return nil }
        return data
    }
}
