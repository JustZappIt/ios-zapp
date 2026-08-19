import ComposableArchitecture
import Foundation
import Testing
import os
@testable import zodl_internal

@Suite
struct IsPortfolioChartEnabledProviderTests {
    @Test
    func preferenceDefaultsOnAndRoundTrips() {
        let storage = UserPreferencesStorage(
            defaultExchangeRate: Data(),
            defaultServer: Data(),
            userDefaults: .portfolioChartTests()
        )

        #expect(storage.portfolioChartEnabled)
        storage.setPortfolioChartEnabled(false)
        #expect(!storage.portfolioChartEnabled)
        storage.setPortfolioChartEnabled(true)
        #expect(storage.portfolioChartEnabled)
        storage.setPortfolioChartEnabled(false)
        storage.removeAll()
        #expect(storage.portfolioChartEnabled)
    }
}

private extension UserDefaultsClient {
    static func portfolioChartTests() -> UserDefaultsClient {
        let storage = OSAllocatedUnfairLock<[String: Any]>(uncheckedState: [:])
        return UserDefaultsClient(
            objectForKey: { key in storage.withLockUnchecked { $0[key] } },
            remove: { key in storage.withLockUnchecked { $0[key] = nil } },
            setValue: { value, key in storage.withLockUnchecked { $0[key] = value } }
        )
    }
}
