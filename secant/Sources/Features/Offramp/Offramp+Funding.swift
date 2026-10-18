// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation

extension Offramp.State {
    var shouldRefreshBaseFunding: Bool {
        page == .amount && showsPayAddFundsPanel
    }

    mutating func updateBaseBalance(from quote: OfframpQuoteModel) {
        guard
            let balance = Decimal(string: quote.baseBalanceDisplay, locale: .current), balance >= 0
        else { return }
        quotedBaseBalance = quote.baseBalanceDisplay
    }
}

extension Offramp {
    private enum FundingCancelID {
        case observation
    }

    /// The empty-wallet panel hides Review, so it cannot rely on another quote to notice an
    /// incoming Base deposit. Refresh only while that panel is visible, and cancel when leaving
    /// or when funds arrive; a failed read retains the previous balance and retries next time.
    func baseFundingObservationEffect(_ shouldObserve: Bool) -> Effect<Action> {
        guard shouldObserve else { return .cancel(id: FundingCancelID.observation) }
        return .run { send in
            while !Task.isCancelled {
                try await continuousClock.sleep(for: .seconds(10))
                do {
                    let account = try await offramp.accountSummary()
                    try Task.checkCancellation()
                    await send(.baseFundingRefreshed(account))
                } catch is CancellationError {
                    return
                } catch {
                    continue
                }
            }
        }
        .cancellable(id: FundingCancelID.observation, cancelInFlight: true)
    }
}
