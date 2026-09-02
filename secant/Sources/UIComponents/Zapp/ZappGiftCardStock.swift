// SPDX-License-Identifier: MIT OR Apache-2.0

import SwiftUI

/// The figure struck into a card's face, on the stocks that earn one.
///
/// One case rather than a flag per ornament, because these are registers and a card belongs to
/// exactly one. That includes the brand mark: a face carrying the Z *and* a design is the brand
/// elbowing into a picture that was finished without it. Making the choice a type rather than a
/// rule means the ladder cannot get it wrong.
enum CardMotif: Equatable {
    /// The Zapp Z, struck into the corner. What a card wears when it has no design of its own.
    case mark(ink: Color)

    /// The splash Z's twin diagonals, swept across the face.
    case sweep(ink: Color)

    /// The same diagonals, heavier and in threes: three tears raked corner to corner.
    case claw(ink: Color)

    /// Guilloché — the banknote line-work. Ceremony where the sweep was energy.
    case rosette(ink: Color)

    /// Interlocking scales, the way lacquerwork carries a dragon. The rarest figure.
    case scales(ink: Color)

    var ink: Color {
        switch self {
        case .mark(let ink), .sweep(let ink), .claw(let ink), .rosette(let ink), .scales(let ink):
            return ink
        }
    }
}

/// The stock a gift card is printed on. Verbatim port of Android's `ZappGiftCardStock`.
///
/// Fixed colours rather than `ZappColors` tokens, and deliberately so — a documented exemption
/// from the token rule: a gift card is an object the sender hands to someone, and the same card
/// has to be the same object in both themes. A clay card that turned cinnabar at dusk would be a
/// different card.
///
/// No stock has a white or near-white face. A card is a gift, and across much of the world a white
/// card is the one handed over at a funeral — so white is spent on ink, on a hairline of sheen and
/// on the strokes of a figure, never on the field itself.
///
/// Colour is spent inward, not on the rim: the lower half of the ladder leaves `edge` a quiet
/// shade of its own face and spends its colour on `figureInk` and `ring`. `edge` turns to metal
/// only in the top stretch, where the stock genuinely *is* a metal, and once a card has a design
/// of its own the branding comes off.
struct ZappGiftCardStock: Equatable {
    static let hairline: CGFloat = 1
    static let foil: CGFloat = 2

    let face: Color
    /// The card seen edge-on. A card with no visible thickness is a rectangle.
    let core: Color
    let edge: Color
    let sheen: Color
    let ink: Color
    let inkMuted: Color
    let inkFaint: Color
    /// Foil. Reserved for the metals at the top; below them the rim stays a shade of the face.
    var edgeWidth: CGFloat = Self.hairline
    /// Which figure the face carries, if any.
    var motif: CardMotif?
    /// The denomination struck in colour rather than plain `ink` — the ladder's main lever. Nil
    /// leaves the figure in ink, which is what the two bare stocks want.
    var figureInk: Color?
    /// A rule set in from the edge, the way a banknote frames its own field — and the colour the
    /// reverse frames itself in, so the two faces of a card are recognisably one card.
    var ring: Color?
    /// Whether the card signs itself "Zapp" along its bottom edge. False from Tiger up: a card
    /// carrying a claw or a dragon is already saying something.
    var showsWordmark = true
}

/// The stocks a card can be printed on, cheapest first. Which one a card gets is decided by the
/// tier ladder — this only says what each looks like. Hex values are Android's, byte for byte.
enum ZappGiftCardStocks {
    /// Clay. Warm dark paper, and the everyday card: a coffee, a round, a thank-you.
    static let clay = ZappGiftCardStock(
        face: Color(argb: 0xFF2A231C),
        core: Color(argb: 0xFF15110D),
        edge: Color(argb: 0xFF453B31),
        sheen: Color(argb: 0x17FFFFFF),
        ink: Color(argb: 0xFFEDE6DB),
        inkMuted: Color(argb: 0xFFA79C8D),
        inkFaint: Color(argb: 0xFF7B7365)
    )

    /// Slate. Still paper, but a cooler and deeper sheet: the first rung up is a change of
    /// temperature rather than of material.
    static let slate = ZappGiftCardStock(
        face: Color(argb: 0xFF1D2226),
        core: Color(argb: 0xFF0E1113),
        edge: Color(argb: 0xFF343C42),
        sheen: Color(argb: 0x1AFFFFFF),
        ink: Color(argb: 0xFFE7ECEF),
        inkMuted: Color(argb: 0xFF9AA3A9),
        inkFaint: Color(argb: 0xFF6E767B)
    )

    /// Cinnabar. A plain charcoal card whose figure is struck in red — the first stock to spend
    /// any colour at all, and it spends it entirely on the number.
    static let cinnabar = ZappGiftCardStock(
        face: Color(argb: 0xFF201E1C),
        core: Color(argb: 0xFF100F0E),
        edge: Color(argb: 0xFF373430),
        sheen: Color(argb: 0x1AFFFFFF),
        ink: Color(argb: 0xFFEDEAE5),
        inkMuted: Color(argb: 0xFFA09A92),
        inkFaint: Color(argb: 0xFF746F68),
        figureInk: Color(argb: 0xFFF06055)
    )

    /// Vermilion. Cinnabar's red, hotter, on a darker card — and the rung where the ring arrives.
    static let vermilion = ZappGiftCardStock(
        face: Color(argb: 0xFF1A1817),
        core: Color(argb: 0xFF0C0B0B),
        edge: Color(argb: 0xFF302D2B),
        sheen: Color(argb: 0x1FFFFFFF),
        ink: Color(argb: 0xFFF2EEE9),
        inkMuted: Color(argb: 0xFFA8A19A),
        inkFaint: Color(argb: 0xFF787269),
        figureInk: Color(argb: 0xFFFF6A57),
        ring: Color(argb: 0x2EFF5A45)
    )

    /// Copper. The first stock to carry the mark, and the last one whose rim stays quiet: the
    /// metal is in the ink and the ring, not round the edge.
    static let copper = ZappGiftCardStock(
        face: Color(argb: 0xFF1F1B17),
        core: Color(argb: 0xFF0F0D0B),
        edge: Color(argb: 0xFF39332C),
        sheen: Color(argb: 0x1AFFE8D0),
        ink: Color(argb: 0xFFF2EBE2),
        inkMuted: Color(argb: 0xFFD08A50),
        inkFaint: Color(argb: 0xFF8A6038),
        motif: .mark(ink: Color(argb: 0x1AD08A50)),
        figureInk: Color(argb: 0xFFE09A5A),
        ring: Color(argb: 0x24C98550)
    )

    /// Amber foil. The brand colour, and the rung where the rim finally becomes metal. The mark
    /// gives way to the splash sweep: the Z stops being stamped and starts being drawn.
    static let amber = ZappGiftCardStock(
        face: Color(argb: 0xFF261B0C),
        core: Color(argb: 0xFF130D05),
        edge: Color(argb: 0xFFFF9417),
        sheen: Color(argb: 0x24FFB26B),
        ink: Color(argb: 0xFFFDF6EC),
        inkMuted: Color(argb: 0xFFC9A47A),
        inkFaint: Color(argb: 0xFF8E7550),
        edgeWidth: ZappGiftCardStock.foil,
        motif: .sweep(ink: Color(argb: 0x24FFB26B)),
        figureInk: Color(argb: 0xFFFFB26B),
        ring: Color(argb: 0x24FF9417)
    )

    /// Tiger. The black card. Three heavy tears raked corner to corner on the splash Z's own
    /// diagonal — the brand's angle, put on the animal rather than on the logo.
    static let tiger = ZappGiftCardStock(
        face: Color(argb: 0xFF0C0A08),
        core: Color(argb: 0xFF040302),
        edge: Color(argb: 0xFF3A2E1E),
        sheen: Color(argb: 0x2EFFA85C),
        ink: Color(argb: 0xFFFDF4E9),
        inkMuted: Color(argb: 0xFFE2A165),
        inkFaint: Color(argb: 0xFF8C6A44),
        edgeWidth: ZappGiftCardStock.foil,
        motif: .claw(ink: Color(argb: 0x38FF9417)),
        figureInk: Color(argb: 0xFFFFB26B),
        ring: Color(argb: 0x2EF07C1E),
        showsWordmark: false
    )

    /// Signature. Gold foil on near-black, and the card that stops shouting: the claw gives way
    /// to engraving. The card you hand someone once.
    static let signature = ZappGiftCardStock(
        face: Color(argb: 0xFF12100C),
        core: Color(argb: 0xFF060504),
        edge: Color(argb: 0xFFE0B056),
        sheen: Color(argb: 0x33E0B056),
        ink: Color(argb: 0xFFF7EFDF),
        inkMuted: Color(argb: 0xFFE0B056),
        inkFaint: Color(argb: 0xFF9C7B3C),
        edgeWidth: ZappGiftCardStock.foil,
        motif: .rosette(ink: Color(argb: 0x1FE0B056)),
        figureInk: Color(argb: 0xFFE0B056),
        ring: Color(argb: 0x2BE0B056),
        showsWordmark: false
    )

    /// Dragon. Red scales under gold, and the top of the ladder. The gold is the card's furniture
    /// and the red is only ever the hide underneath it. Unsigned and unmarked, which is most of
    /// why it reads as the best card in the deck.
    static let dragon = ZappGiftCardStock(
        face: Color(argb: 0xFF14090A),
        core: Color(argb: 0xFF080405),
        edge: Color(argb: 0xFFE8C06A),
        sheen: Color(argb: 0x33F0D392),
        ink: Color(argb: 0xFFFBF2E2),
        inkMuted: Color(argb: 0xFFE8C06A),
        inkFaint: Color(argb: 0xFF9C8248),
        edgeWidth: ZappGiftCardStock.foil,
        motif: .scales(ink: Color(argb: 0x40F0483A)),
        figureInk: Color(argb: 0xFFF2D289),
        ring: Color(argb: 0x33E8C06A),
        showsWordmark: false
    )

    /// Collected. Grey where the others are warm — the colour has drained out of it — but still
    /// clearly lighter than the page, because a card you cannot pick out of the background is a
    /// hole in the stack rather than a settled card.
    static let spent = ZappGiftCardStock(
        face: Color(argb: 0xFF2E2C29),
        core: Color(argb: 0xFF1A1917),
        edge: Color(argb: 0xFF474440),
        sheen: Color(argb: 0x14FFFFFF),
        ink: Color(argb: 0xFFAAA59D),
        inkMuted: Color(argb: 0xFF847F77),
        inkFaint: Color(argb: 0xFF666159)
    )

    /// The mark on a card that is still out there, whatever stock it is printed on.
    static let liveMark = Color(argb: 0xFFFF9417)
}

private extension Color {
    /// Android's `0xAARRGGBB` literals, byte for byte, in sRGB.
    init(argb: UInt64) {
        let alpha = Double((argb >> 24) & 0xFF) / 255
        let red = Double((argb >> 16) & 0xFF) / 255
        let green = Double((argb >> 8) & 0xFF) / 255
        let blue = Double(argb & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
