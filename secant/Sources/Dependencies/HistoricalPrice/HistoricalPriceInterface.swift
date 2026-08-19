// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture

extension DependencyValues {
    var historicalPrice: HistoricalPriceClient {
        get { self[HistoricalPriceClient.self] }
        set { self[HistoricalPriceClient.self] = newValue }
    }
}

@DependencyClient
struct HistoricalPriceClient {
    var states: @Sendable (PriceDateRange, CurrencyISO4217) -> AsyncStream<HistoricalPriceState> = { _, _ in
        AsyncStream { continuation in
            continuation.yield(.unavailable())
            continuation.finish()
        }
    }
}
