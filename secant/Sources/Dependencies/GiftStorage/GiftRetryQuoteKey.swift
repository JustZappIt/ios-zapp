// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation

/// Holds the priced retry quote between the review sheet and the confirm tap.
///
/// Outside `State` because the quote carries the card's mnemonic, and TCA state is `Equatable`
/// and gets dumped by debug tooling and test failures — the same reason the raw link travels as a
/// token rather than as navigation state.
///
/// A dependency rather than a stored property on the reducer: `Root.body` is recomputed on every
/// action, so a `Scope { GiftCardList() }` builds a fresh reducer — and a fresh box — each time. A
/// quote written by one action would not be there for the next, which is the whole of this type's
/// job.
final class GiftRetryQuoteStore: @unchecked Sendable {
    private let lock = NSLock()
    private var quote: GiftFundingQuote?

    func put(_ quote: GiftFundingQuote?) {
        lock.lock()
        defer { lock.unlock() }
        self.quote = quote
    }

    func take() -> GiftFundingQuote? {
        lock.lock()
        defer { lock.unlock() }
        return quote
    }
}

extension DependencyValues {
    var giftRetryQuote: GiftRetryQuoteStore {
        get { self[GiftRetryQuoteStoreKey.self] }
        set { self[GiftRetryQuoteStoreKey.self] = newValue }
    }
}

private enum GiftRetryQuoteStoreKey: DependencyKey {
    static let liveValue = GiftRetryQuoteStore()
    static let testValue = GiftRetryQuoteStore()
}
