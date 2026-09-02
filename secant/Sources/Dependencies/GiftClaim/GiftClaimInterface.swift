// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
@preconcurrency import ZcashLightClientKit

extension DependencyValues {
    var giftClaim: GiftClaimClient {
        get { self[GiftClaimClient.self] }
        set { self[GiftClaimClient.self] = newValue }
    }
}

struct GiftClaimRequest: Sendable {
    let payload: GiftLinkPayload
    let cardAddress: String
    let networkType: NetworkType
    let endpoint: LightWalletEndpoint
    let recipientAddress: String
    let resumeEvidence: GiftClaimResumeEvidence
    /// The irreversible boundary: the caller's receipt marker. A throw here means the engine never
    /// enters its shielded create-and-submit section.
    let onBeforeSubmit: @Sendable () async throws -> Void
    let onProgress: @Sendable (GiftClaimProgress) -> Void
}

struct GiftInspectRequest: Sendable {
    let payload: GiftLinkPayload
    let cardAddress: String
    let networkType: NetworkType
    let endpoint: LightWalletEndpoint
    let fundingTxid: String
    let onProgress: @Sendable (GiftClaimProgress) -> Void
}

struct GiftFinalizeInspectRequest: Sendable {
    let payload: GiftLinkPayload
    let cardAddress: String
    let networkType: NetworkType
    let endpoint: LightWalletEndpoint
}

/// Runs a gift card's own throwaway wallet, long enough to move its funds into this one.
///
/// A second, entirely separate `SDKSynchronizer` — never the app's own, which holds the user's
/// real funds and has no business hosting a bearer seed. Each call opens, works and tears down
/// internally, so no caller can leak a bearer seed into a lingering scan. The SDK has no
/// in-process alias guard, so the per-address claim lock around these calls is the only thing
/// preventing two live instances on one card; nothing else in the app may construct a synchronizer
/// with a `gift_` alias.
@DependencyClient
struct GiftClaimClient {
    /// Syncs the card's wallet and moves at least the advertised amount to the recipient.
    /// Spendable top-ups are swept so no recoverable funds are discarded with the isolated wallet.
    var claim: @Sendable (GiftClaimRequest) async throws -> GiftClaimOutcome

    /// Syncs the card's wallet and reports what it holds, spending nothing. The only way to learn
    /// whether a card was collected: the note is shielded, so nothing short of scanning with the
    /// card's own viewing key can see it spent.
    var inspect: @Sendable (GiftInspectRequest) async throws -> GiftCardHoldings

    /// Whether the card's own wallet shows a final claim spend with at most fee-reserve dust left,
    /// so the receipt may settle and the database may be deleted.
    var inspectFinalization: @Sendable (GiftFinalizeInspectRequest) async throws -> GiftClaimFinalization

    /// Deletes the card's isolated wallet directory. Throws when deletion fails — the caller must
    /// not settle a receipt whose database survived.
    var cleanupFinalizedClaim: @Sendable (_ networkName: String, _ cardAddress: String) async throws -> Void
}
