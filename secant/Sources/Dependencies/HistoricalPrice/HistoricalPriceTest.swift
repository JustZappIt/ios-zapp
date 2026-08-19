// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture

extension HistoricalPriceClient: TestDependencyKey {
    static let testValue = HistoricalPriceClient()
}
