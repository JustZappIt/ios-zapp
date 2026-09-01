// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
@preconcurrency import ZcashLightClientKit

/// What one on-request scan of a card's own wallet turned out to mean for the sender.
enum GiftCardCheckResult: Equatable {
    /// The funding arrived and a final claim spend emptied the card. Recorded durably.
    case collected
    /// The funds are still sitting on the card.
    case waiting
    /// The card was never funded, so there was nothing to look for and nothing was scanned.
    case notFunded
    /// The funding is in the mempool or dropped — and a dropped one can still mine until it
    /// expires — so nothing can have been collected yet.
    case fundingPending
    /// The card's server could not be reached; nothing was learned about the card.
    case unreachable
    /// Something else went wrong, or a terminal answer could not be recorded terminal.
    case unknown
}

/// Answers "did they open it?" for one card, on request — each check is a full multi-minute scan,
/// so it runs one card at a time and never as a background sweep.
struct CheckGiftCardClaimed {
    @Dependency(\.date) var date
    @Dependency(\.giftCardStorage) var giftCardStorage
    @Dependency(\.giftClaim) var giftClaim
    @Dependency(\.zcashSDKEnvironment) var zcashSDKEnvironment

    func callAsFunction(
        cardId: String,
        onProgress: @escaping @Sendable (GiftClaimProgress) -> Void
    ) async -> GiftCardCheckResult {
        guard let card = try? await giftCardStorage.get(cardId) else { return .unknown }
        // Never scan an unfunded card: nothing was ever sent, so there is nothing to look for.
        guard let fundingTxid = card.fundingTxid else { return .notFunded }

        let holdings: GiftCardHoldings
        do {
            holdings = try await giftClaim.inspect(
                GiftInspectRequest(
                    payload: card.toLinkPayload(),
                    cardAddress: card.address,
                    networkType: zcashSDKEnvironment.network().networkType,
                    endpoint: zcashSDKEnvironment.endpoint(),
                    fundingTxid: fundingTxid,
                    onProgress: onProgress
                )
            )
        } catch let error as GiftClaimEngineError {
            switch error {
            case .unreachable, .scanStalled:
                // "You are offline" and "something went wrong" need different copy, and neither
                // says anything about the card.
                return .unreachable
            case .stopped, .paramsUnavailable:
                return .unknown
            }
        } catch is CancellationError {
            return .unknown
        } catch {
            return .unknown
        }

        if holdings.isCollected {
            // Terminal, so it must be recorded terminal: return collected only if the durable
            // write succeeded.
            do {
                try await giftCardStorage.markClaimed(cardId, GiftLinkCodec.instantString(from: date.now()))
                return .collected
            } catch {
                return .unknown
            }
        }
        if holdings.isEmpty && !holdings.hasFundingArrived {
            // Deliberately not recorded via recordChecked: that field claims the card still held
            // its funds, and here nothing has arrived yet.
            return .fundingPending
        }
        try? await giftCardStorage.recordChecked(cardId, GiftLinkCodec.instantString(from: date.now()))
        return .waiting
    }
}
