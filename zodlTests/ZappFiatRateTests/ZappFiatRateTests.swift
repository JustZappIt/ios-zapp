import ComposableArchitecture
import Foundation
import Testing
@testable import zodl_internal

@Suite struct ZappFiatRateTests {
    private let now = Date(timeIntervalSince1970: 10_000)

    @Test func automaticConversionMustBeEnabled() {
        let preference = UserPreferencesStorage.ExchangeRate(
            manual: false,
            automatic: false,
            currency: .usd
        )

        let result = ZappFiatRate.resolve(
            preference: preference,
            conversion: CurrencyConversion(.usd, ratio: 20, timestamp: 1),
            fallback: quote(),
            at: now
        )

        #expect(result == nil)
    }

    @Test func primaryConversionMustMatchSelectedCurrency() {
        let result = ZappFiatRate.resolve(
            preference: preference(.eur),
            conversion: CurrencyConversion(.usd, ratio: 20, timestamp: 1),
            fallback: quote(),
            at: now
        )

        #expect(result == nil)
    }

    @Test func matchingPrimaryConversionWins() {
        let primary = CurrencyConversion(.usd, ratio: 20, timestamp: 1)

        let result = ZappFiatRate.resolve(
            preference: preference(.usd),
            conversion: primary,
            fallback: quote(ratio: 30),
            at: now
        )

        #expect(result == primary)
    }

    @Test func freshFallbackPreservesSourceTimestamp() {
        let fallback = quote(ratio: 30, age: 60)

        let result = ZappFiatRate.resolve(
            preference: preference(.usd),
            conversion: nil,
            fallback: fallback,
            at: now
        )

        #expect(result?.iso4217 == .usd)
        #expect(result?.ratio == 30)
        #expect(result?.timestamp == fallback.fetchedAt.timeIntervalSince1970)
    }

    @Test func staleFallbackIsRejected() {
        let result = ZappFiatRate.resolve(
            preference: preference(.usd),
            conversion: nil,
            fallback: quote(age: ZappFiatQuote.lifetime + 1),
            at: now
        )

        #expect(result == nil)
    }

    @Test func quoteUsesTheCanonicalZecAsset() {
        let quote = ZappFiatQuote(
            swapAssets: [asset(price: 42)],
            fetchedAt: now
        )

        #expect(quote?.currency == .usd)
        #expect(quote?.ratio == 42)
        #expect(quote?.fetchedAt == now)
    }

    @Test func quoteRejectsNonPositivePrices() {
        let quote = ZappFiatQuote(
            swapAssets: [asset(price: 0)],
            fetchedAt: now
        )

        #expect(quote == nil)
    }

    @Test func fallbackRefreshRequiresAutomaticUSD() {
        #expect(ZappFiatRate.shouldRefreshFallback(
            preference: preference(.usd),
            fallback: nil,
            isLoading: false,
            at: now
        ))
        #expect(!ZappFiatRate.shouldRefreshFallback(
            preference: preference(.eur),
            fallback: nil,
            isLoading: false,
            at: now
        ))
        #expect(!ZappFiatRate.shouldRefreshFallback(
            preference: nil,
            fallback: nil,
            isLoading: false,
            at: now
        ))
    }

    @Test func fallbackRefreshSkipsFreshOrInFlightQuotes() {
        #expect(!ZappFiatRate.shouldRefreshFallback(
            preference: preference(.usd),
            fallback: quote(age: 1),
            isLoading: false,
            at: now
        ))
        #expect(!ZappFiatRate.shouldRefreshFallback(
            preference: preference(.usd),
            fallback: nil,
            isLoading: true,
            at: now
        ))
    }

    private func preference(_ currency: CurrencyISO4217) -> UserPreferencesStorage.ExchangeRate {
        UserPreferencesStorage.ExchangeRate(manual: false, automatic: true, currency: currency)
    }

    private func quote(ratio: Double = 30, age: TimeInterval = 0) -> ZappFiatQuote {
        ZappFiatQuote(
            currency: .usd,
            ratio: ratio,
            fetchedAt: now.addingTimeInterval(-age)
        )
    }

    private func asset(price: Decimal) -> SwapAsset {
        SwapAsset(
            provider: "near",
            chain: "zec",
            token: "zec",
            assetId: "zec",
            usdPrice: price,
            decimals: 8
        )
    }
}
