// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
@preconcurrency import ZcashLightClientKit

/// ISO 7810 ID-1. A card that is not this shape reads as a panel calling itself a card.
let giftCardAspect: CGFloat = 1.586

/// Where a denomination sits on the ladder.
///
/// A gift card has no recipient to name it by, so a deck needs something else to tell cards apart
/// at a glance — and a sender filling in an amount deserves to see the gift get better as the
/// figure climbs. Denomination is the one thing every card has, so it decides both.
enum GiftCardTier: Equatable {
    /// Under 0.1 ZEC.
    case clay
    /// 0.1 to 0.25 ZEC.
    case slate
    /// 0.25 to 0.5 ZEC. The first red.
    case cinnabar
    /// 0.5 to 1 ZEC.
    case vermilion
    /// 1 to 2 ZEC.
    case copper
    /// 2 to 5 ZEC.
    case amber
    /// 5 to 10 ZEC. The black card.
    case tiger
    /// 10 to 50 ZEC.
    case signature
    /// 50 ZEC and up.
    case dragon
    /// Collected. Overrides denomination: a spent card is a receipt, not a gift.
    case spent

    var stock: ZappGiftCardStock {
        switch self {
        case .clay: return ZappGiftCardStocks.clay
        case .slate: return ZappGiftCardStocks.slate
        case .cinnabar: return ZappGiftCardStocks.cinnabar
        case .vermilion: return ZappGiftCardStocks.vermilion
        case .copper: return ZappGiftCardStocks.copper
        case .amber: return ZappGiftCardStocks.amber
        case .tiger: return ZappGiftCardStocks.tiger
        case .signature: return ZappGiftCardStocks.signature
        case .dragon: return ZappGiftCardStocks.dragon
        case .spent: return ZappGiftCardStocks.spent
        }
    }
}

private let zatoshiPerZec = Zatoshi.Constants.oneZecInZatoshi

// The boundaries have not moved since the ladder was first drawn — only the stock printed on each
// side of them has. A card made before a restyle lands on the same rung it always did, wearing
// whatever that rung looks like now.
private let giftCardLadder: [(ceiling: Int64, tier: GiftCardTier)] = [
    (zatoshiPerZec / 10, .clay),
    (zatoshiPerZec / 4, .slate),
    (zatoshiPerZec / 2, .cinnabar),
    (zatoshiPerZec, .vermilion),
    (zatoshiPerZec * 2, .copper),
    (zatoshiPerZec * 5, .amber),
    (zatoshiPerZec * 10, .tiger),
    (zatoshiPerZec * 50, .signature)
]

/// Shared by the sender's deck, the create flow's live preview and the recipient's claim screen,
/// so a card that was handed over as amber is the same amber card when it arrives.
func giftCardTier(amountZatoshi: Int64, isSettled: Bool) -> GiftCardTier {
    if isSettled { return .spent }
    return giftCardLadder.first { amountZatoshi < $0.ceiling }?.tier ?? .dragon
}

/// How a card prints its denomination: ZEC with trailing zeros trimmed, ticker after.
///
/// The wallet's default Zatoshi formatting pads to three decimals so figures line up down a
/// column, which is right in a transaction list and wrong on a card: this figure is a hero with
/// nothing to align to, and `10.000 ZEC` claims a precision the gift has not got.
func giftAmountText(_ zatoshi: Zatoshi) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 8
    formatter.minimumIntegerDigits = 1
    let number = formatter.string(from: zatoshi.decimalValue) ?? zatoshi.decimalString()
    return "\(number) \(TargetConstants.tokenName)"
}
