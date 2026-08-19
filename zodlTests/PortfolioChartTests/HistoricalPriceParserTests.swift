import Foundation
import Testing
@testable import zodl_internal

@Suite
struct HistoricalPriceParserTests {
    private var range: PriceDateRange {
        guard let from = HistoricalPriceDate.parseDay("2026-08-01"),
            let to = HistoricalPriceDate.parseDay("2026-08-03") else {
            preconditionFailure("Invalid test range")
        }
        return PriceDateRange(from: from, to: to)
    }

    @Test
    func validPageParses() throws {
        let page = try #require(try? parse(validBody()).get())

        #expect(page.points.count == 3)
        #expect(page.points[0].fiatPerZec == Decimal(10))
        #expect(page.complete)
        #expect(page.nextCursor == nil)
    }

    @Test
    func rejectsNonBoundaryTimestamp() {
        expectInvalid(validBody().replacingOccurrences(of: "2026-08-02T00:00:00Z", with: "2026-08-02T01:00:00Z"))
    }

    @Test
    func rejectsUnorderedOrDuplicateTimestamps() {
        expectInvalid(validBody().replacingOccurrences(of: "2026-08-02T00:00:00Z", with: "2026-08-01T00:00:00Z"))
    }

    @Test
    func rejectsPointOutsideResponseBounds() {
        expectInvalid(validBody().replacingOccurrences(of: "2026-08-03T00:00:00Z", with: "2026-08-04T00:00:00Z"))
    }

    @Test
    func rejectsMissingAndNonPositivePriceFields() {
        expectInvalid(validBody().replacingOccurrences(of: "\"price\":20,", with: ""))
        expectInvalid(validBody().replacingOccurrences(of: "\"price\":20", with: "\"price\":0"))
    }

    @Test
    func rejectsContradictoryPriceFields() {
        expectInvalid(validBody().replacingOccurrences(of: "\"priceUsd\":20", with: "\"priceUsd\":21"))
    }

    @Test
    func rejectsNonUnitUsdConversion() {
        expectInvalid(validBody().replacingOccurrences(of: "\"unitsPerUsd\":1", with: "\"unitsPerUsd\":2"))
    }

    @Test
    func rejectsContradictoryBoundsAndMetadata() {
        expectInvalid(validBody().replacingOccurrences(of: "\"from\":\"2026-08-01T00:00:00Z\"", with: "\"from\":\"2026-07-31T00:00:00Z\""))
        expectInvalid(validBody().replacingOccurrences(of: "\"dataAsOf\":\"2026-08-03T00:00:00Z\"", with: "\"dataAsOf\":\"2026-08-02T00:00:00Z\""))
    }

    @Test
    func rejectsCompletePageWithCursor() {
        expectInvalid(validBody().replacingOccurrences(of: "\"nextCursor\":null", with: "\"nextCursor\":\"2026-08-03T00:00:00Z\""))
    }

    @Test
    func mapsSeriesUnavailableSentinel() {
        let data = Data(#"{"error":{"code":"SERIES_UNAVAILABLE","message":"missing"}}"#.utf8)
        #expect(parseHistoricalPriceError(status: 404, data: data) == .seriesUnavailable)
    }

    /// Availability entirely after the requested range would reach the ALL period, which builds its
    /// window from `availableFrom` — an inverted range there traps on `PriceDateRange`'s
    /// precondition, so a response must never get that far.
    @Test
    func rejectsAvailabilityAfterTheRequestedRange() {
        expectInvalid(
            validBody()
                .replacingOccurrences(of: #""availableFrom":"2026-08-01T00:00:00Z""#, with: #""availableFrom":"2030-01-01T00:00:00Z""#)
                .replacingOccurrences(of: #""availableTo":"2026-08-03T00:00:00Z""#, with: #""availableTo":"2030-01-02T00:00:00Z""#)
                .replacingOccurrences(of: #""dataAsOf":"2026-08-03T00:00:00Z""#, with: #""dataAsOf":"2030-01-02T00:00:00Z""#)
        )
    }

    @Test
    func rejectsAvailabilityBeforeTheRequestedRange() {
        expectInvalid(
            validBody()
                .replacingOccurrences(of: #""availableFrom":"2026-08-01T00:00:00Z""#, with: #""availableFrom":"2020-01-01T00:00:00Z""#)
                .replacingOccurrences(of: #""availableTo":"2026-08-03T00:00:00Z""#, with: #""availableTo":"2020-01-02T00:00:00Z""#)
                .replacingOccurrences(of: #""dataAsOf":"2026-08-03T00:00:00Z""#, with: #""dataAsOf":"2020-01-02T00:00:00Z""#)
        )
    }

    private func parse(_ body: String) -> Result<HistoricalPricePage, PricingFailure> {
        parseHistoricalPricePage(data: Data(body.utf8), requestedRange: range, requestedFiat: .usd)
    }

    private func expectInvalid(_ body: String) {
        guard case .failure(.invalidResponse) = parse(body) else {
            Issue.record("Expected strict parser rejection")
            return
        }
    }

    private func validBody() -> String {
        #"""
        {
            "asset":"ZEC","fiat":"USD","resolution":"1d",
            "from":"2026-08-01T00:00:00Z","to":"2026-08-03T00:00:00Z",
            "availableFrom":"2026-08-01T00:00:00Z","availableTo":"2026-08-03T00:00:00Z",
            "dataAsOf":"2026-08-03T00:00:00Z","complete":true,"nextCursor":null,
            "points":[
                {"timestamp":"2026-08-01T00:00:00Z","price":10,"priceUsd":10,"unitsPerUsd":1},
                {"timestamp":"2026-08-02T00:00:00Z","price":20,"priceUsd":20,"unitsPerUsd":1},
                {"timestamp":"2026-08-03T00:00:00Z","price":30,"priceUsd":30,"unitsPerUsd":1}
            ]
        }
        """#
    }
}
