import Foundation
import Testing
@preconcurrency import ZcashLightClientKit
@testable import zodl_internal

@Suite
struct BalanceChartVMTests {
    @Test
    func zecFallbackIncludesWindowBaselineAndCurrentBalance() throws {
        let now = day("2026-08-10")
        let cutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let history = ZappBalanceHistory.reconciled(
            points: [
                .init(timestamp: day("2026-08-01"), balance: Zatoshi(100)),
                .init(timestamp: day("2026-08-05"), balance: Zatoshi(150))
            ],
            confirmedBalance: Zatoshi(150)
        )

        let points = try #require(zecChartPoints(balanceHistory: history, period: .week, now: now))

        #expect(points.map(\.timestamp) == [cutoff, day("2026-08-05"), now])
        #expect(points.map(\.value) == [100, 150, 150])
    }

    @Test
    func zecFallbackRejectsInconsistentHistory() {
        #expect(zecChartPoints(balanceHistory: .inconsistent, period: .week, now: Date()) == nil)
    }

    @Test
    func allRangeUsesSharedDefaultThenAvailabilityStart() {
        let completed = day("2026-08-10")
        let available = day("2024-01-01")

        #expect(standardizedPriceRange(period: .all, completedDate: completed).from == day("2026-08-03"))
        #expect(standardizedPriceRange(period: .all, completedDate: completed, availableFrom: available).from == available)
    }

    private func day(_ value: String) -> Date {
        guard let date = HistoricalPriceDate.parseDay(value) else {
            preconditionFailure("Invalid test date: \(value)")
        }
        return date
    }
}
