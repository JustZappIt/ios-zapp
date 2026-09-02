// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation

/// Destroying the gift keychain records now would strand money only they can reach.
struct UnsharedGiftFundsError: Error, Equatable {}

/// The guard on every path that destroys the gift keychain records — a guard on one destructive
/// path and not another is the same bug with extra steps.
///
/// Blocks for sender cards with unshared funds and for received gifts that are not settled. An
/// unreadable store also blocks: guessing "empty" wrong destroys money.
struct EnsureNoUnsharedGiftFunds {
    @Dependency(\.giftCardStorage) var giftCardStorage
    @Dependency(\.receivedGiftStorage) var receivedGiftStorage

    func callAsFunction() async throws {
        guard
            let unsharedFunds = try? await giftCardStorage.hasUnsharedFunds(nil),
            let unsettledClaims = try? await receivedGiftStorage.hasUnsettledClaims()
        else { throw UnsharedGiftFundsError() }
        if unsharedFunds || unsettledClaims {
            throw UnsharedGiftFundsError()
        }
    }
}
