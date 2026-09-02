// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation

/// Hands a gift link out and records that it left the device.
///
/// Opening the share sheet is not the hand-off, and the whole design turns on that. The record of
/// a hand-off releases the reset guard, and the reset wipes the only copy of an unshared card's
/// seed. A sender who opened the sheet and changed their mind would otherwise be left with a card
/// marked as given away, holding real money, one wallet reset from gone. So only a completed
/// share — or a copy, the one hand-off route that always reports its own outcome — marks the card.
///
/// The link is the money, so it never reaches a log, a notification or a crash report.
struct ShareGiftLink {
    @Dependency(\.date) var date
    @Dependency(\.giftCardStorage) var giftCardStorage

    /// Re-reads the card from storage immediately before handing its link out, and rebuilds the
    /// link from the record — never a cached string. Nil when the card can no longer be handed
    /// off; the caller flips to its unavailable state rather than sharing.
    func currentHandOff(cardId: String) async -> (card: StoredGiftCard, link: String)? {
        guard
            let card = try? await giftCardStorage.get(cardId),
            card.canBeHandedOff,
            let link = try? GiftLinkCodec.encode(card.toLinkPayload())
        else { return nil }
        return (card, link)
    }

    /// Records that the link left the device — a completed share sheet, or the clipboard, which is
    /// an affirmative act reporting no outcome of its own.
    ///
    /// Best-effort by design: the link is already out, so failing to record that must not read as
    /// a failed share. Callers that can tell the sender the record failed should — an unmarked
    /// card keeps blocking the wallet reset, and doing that silently is how the guard turns into a
    /// wallet nobody can delete.
    @discardableResult
    func markHandedOut(cardId: String) async -> Bool {
        do {
            try await giftCardStorage.markShared(cardId, GiftLinkCodec.instantString(from: date.now()))
            return true
        } catch {
            return false
        }
    }
}

extension StoredGiftCard {
    /// Sharing is refused only for a claimed card and for one nothing was ever sent to. A card
    /// whose broadcast outcome was never seen stays shareable: its money may be gone, and then the
    /// link is the only route to it.
    var canBeHandedOff: Bool {
        status != .claimed && hasFundingAttempt
    }
}
