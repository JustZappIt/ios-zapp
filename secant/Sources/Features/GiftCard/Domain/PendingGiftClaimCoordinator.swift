// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation

extension DependencyValues {
    var pendingGiftClaimCoordinator: PendingGiftClaimCoordinatorClient {
        get { self[PendingGiftClaimCoordinatorClient.self] }
        set { self[PendingGiftClaimCoordinatorClient.self] = newValue }
    }
}

/// Reopens unsettled claims: called from Root at startup and on every foreground, skipped while
/// the claim screen is already up (two screens would race one card).
@DependencyClient
struct PendingGiftClaimCoordinatorClient {
    /// Reconciles finished claims first, then registers the link of one claim that still has
    /// recovery work left and returns its intake token — nil when none, refused, or already
    /// pending.
    ///
    /// Scoped to receipts that actually started a claim (`isUnsettledClaim`). A receipt is
    /// written before the scan, so an unscoped sweep would also reopen the screen for every card
    /// the wallet merely read — on every single foreground, for good, over a gift that was never
    /// taken.
    var resumeNext: @Sendable () async -> String?
}

extension PendingGiftClaimCoordinatorClient: DependencyKey {
    static let liveValue = PendingGiftClaimCoordinatorClient.live()

    static func live() -> Self {
        let gate = KeyedAsyncLock()
        return Self(
            resumeNext: {
                try? await gate.withLock("resume") {
                    @Dependency(\.pendingGiftLinks) var pendingGiftLinks
                    @Dependency(\.receivedGiftStorage) var receivedGiftStorage
                    await ConfirmGiftClaim().reconcile()
                    guard
                        let receipt = try? await receivedGiftStorage.getAll()
                            .first(where: { $0.isUnsettledClaim && $0.claimLink != nil }),
                        let payload = receipt.claimLink,
                        let link = try? GiftLinkCodec.encode(payload),
                        case .accepted(let token) = pendingGiftLinks.put(link)
                    else { return nil }
                    return token
                } ?? nil
            }
        )
    }
}
