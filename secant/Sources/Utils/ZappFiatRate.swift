import ComposableArchitecture
import Foundation
@preconcurrency import ZcashLightClientKit

struct ZappFiatQuote: Equatable {
    static let lifetime: TimeInterval = 15 * 60

    let currency: CurrencyISO4217
    let ratio: Double
    let fetchedAt: Date

    init?(
        swapAssets: IdentifiedArrayOf<SwapAsset>,
        fetchedAt: Date
    ) {
        guard let asset = swapAssets[id: SwapConstants.zecAssetIdOnNear] else {
            return nil
        }

        let ratio = NSDecimalNumber(decimal: asset.usdPrice).doubleValue
        guard ratio > 0 else {
            return nil
        }

        self.currency = .usd
        self.ratio = ratio
        self.fetchedAt = fetchedAt
    }

    init(currency: CurrencyISO4217, ratio: Double, fetchedAt: Date) {
        self.currency = currency
        self.ratio = ratio
        self.fetchedAt = fetchedAt
    }

    func isFresh(at date: Date) -> Bool {
        let age = date.timeIntervalSince(fetchedAt)
        return age >= 0 && age <= Self.lifetime
    }
}

enum ZappFiatRate {
    static func shouldRefreshFallback(
        preference: UserPreferencesStorage.ExchangeRate?,
        fallback: ZappFiatQuote?,
        isLoading: Bool,
        at date: Date
    ) -> Bool {
        preference?.automatic == true
            && preference?.currency == .usd
            && !isLoading
            && fallback?.isFresh(at: date) != true
    }

    static func resolve(
        preference: UserPreferencesStorage.ExchangeRate?,
        conversion: CurrencyConversion?,
        fallback: ZappFiatQuote?,
        at date: Date
    ) -> CurrencyConversion? {
        guard let preference, preference.automatic else {
            return nil
        }

        if let conversion, conversion.iso4217 == preference.currency {
            return conversion
        }

        guard
            let fallback,
            fallback.currency == preference.currency,
            fallback.isFresh(at: date)
        else {
            return nil
        }

        return CurrencyConversion(
            fallback.currency,
            ratio: fallback.ratio,
            timestamp: fallback.fetchedAt.timeIntervalSince1970
        )
    }
}
