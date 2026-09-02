// SPDX-License-Identifier: MIT OR Apache-2.0

import SwiftUI

/// What a card picks up as its denomination climbs.
///
/// Struck into the face rather than laid on top of it: everything here is drawn at low opacity, so
/// it reads as something done to the material rather than a graphic sitting on it.
///
/// Drawn outside in: the ring is the field's boundary, then whichever motif the stock carries. One
/// only — the Zapp Z is itself a motif here, so a card that has a design of its own cannot also be
/// stamped with the logo.
///
/// `isReverse` is the back of the card, which has no figure and no wordmark to work around, so the
/// scale field spreads over the whole surface there; the ring is skipped — the back draws its own
/// inner frame, and a ring inside that is two frames deep.
struct GiftCardFlare: View {
    let stock: ZappGiftCardStock
    let corner: CGFloat
    var isReverse = false

    var body: some View {
        if stock.motif != nil || stock.ring != nil {
            Canvas { context, size in
                if let ring = stock.ring, !isReverse {
                    drawRing(context: context, size: size, ink: ring)
                }
                switch stock.motif {
                case .mark(let ink):
                    drawMark(context: context, size: size, ink: ink)
                case .sweep(let ink):
                    drawDiagonals(context: context, size: size, ink: ink, count: 2, width: 0.018)
                case .claw(let ink):
                    drawDiagonals(context: context, size: size, ink: ink, count: 3, width: 0.055)
                case .rosette(let ink):
                    drawRosette(context: context, size: size, ink: ink)
                case .scales(let ink):
                    drawScales(context: context, size: size, ink: ink, fieldLeft: isReverse ? 0 : 0.46)
                case nil:
                    break
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// The field's own boundary, drawn under everything that sits inside it. Set in far enough to
    /// clear the foil edge and the face's own text padding.
    private func drawRing(context: GraphicsContext, size: CGSize, ink: Color) {
        let inset = min(size.width, size.height) * 0.055
        let radius = max(corner - inset, 0)
        let rect = CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
        context.stroke(
            Path(roundedRect: rect, cornerRadius: radius),
            with: .color(ink),
            lineWidth: 0.8
        )
    }

    /// The splash Z's accent diagonals, in card terms: the run keeps the brand's angle instead of
    /// defaulting to 45 degrees, and every stroke runs edge to edge — a diagonal that stops short
    /// is a scuff. What separates the sweep and the claw is only count and weight.
    private func drawDiagonals(context: GraphicsContext, size: CGSize, ink: Color, count: Int, width: CGFloat) {
        let run = size.height * 0.4912
        let gap = size.width * 0.11
        let stroke = size.height * width
        for stripe in 0..<count {
            let head = size.width * 0.58 + gap * CGFloat(stripe)
            var path = Path()
            path.move(to: CGPoint(x: head, y: 0))
            path.addLine(to: CGPoint(x: head - run, y: size.height))
            context.stroke(path, with: .color(ink), lineWidth: stroke)
        }
    }

    /// The Zapp Z, struck into the bottom corner. Drawn rather than set: a text glyph would
    /// inherit whatever face the system feels like, and this has to be the same mark on every card
    /// that carries it.
    private func drawMark(context: GraphicsContext, size: CGSize, ink: Color) {
        let height = size.height * 0.2
        let pad = corner + 4
        let bottomRight = CGPoint(x: size.width - pad, y: size.height - pad)
        let width = height * 0.78
        let left = bottomRight.x - width
        let top = bottomRight.y - height
        var path = Path()
        path.move(to: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: bottomRight.x, y: top))
        path.addLine(to: CGPoint(x: left, y: bottomRight.y))
        path.addLine(to: CGPoint(x: bottomRight.x, y: bottomRight.y))
        context.stroke(path, with: .color(ink), lineWidth: height * 0.14)
    }

    /// A hypotrochoid — the spirograph curve behind the numerals on a banknote. Three turns of a
    /// 7/3 rose: dense enough to read as engraving, open enough not to grey out.
    private func drawRosette(context: GraphicsContext, size: CGSize, ink: Color) {
        let outer: CGFloat = 7
        let inner: CGFloat = 3
        let offset: CGFloat = 5
        let radius = min(size.width, size.height) * 0.62
        let centre = CGPoint(x: size.width - radius * 0.75, y: size.height / 2)
        let scale = radius / (outer - inner + offset)
        var path = Path()
        for step in 0...270 {
            let parameter = CGFloat(step) * 0.0698
            let ratio = (outer - inner) / inner
            let x = centre.x + ((outer - inner) * cos(parameter) + offset * cos(ratio * parameter)) * scale
            let y = centre.y + ((outer - inner) * sin(parameter) - offset * sin(ratio * parameter)) * scale
            if step == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        context.stroke(path, with: .color(ink), lineWidth: 0.6)
    }

    /// A field of interlocking scales. Each scale is the lower half of a circle, rows overlap by
    /// half a scale so every arc tucks under the two above it — drawn as separate arcs they are
    /// fish tiles, drawn overlapping they are hide. Rows alternate by half a scale sideways so the
    /// seams never line up into columns.
    private func drawScales(context: GraphicsContext, size: CGSize, ink: Color, fieldLeft: CGFloat) {
        let scale = size.height * 0.19
        let left = size.width * fieldLeft
        let rows = Int(size.height / (scale * 0.52)) + 2
        let columns = Int((size.width - left) / scale) + 2
        var clipped = context
        clipped.clip(to: Path(CGRect(x: left, y: 0, width: size.width - left, height: size.height)))
        for row in 0..<rows {
            let y = CGFloat(row) * scale * 0.52 - scale
            let stagger = row % 2 == 0 ? 0 : scale / 2
            for column in 0..<columns {
                let origin = CGPoint(x: left - scale + stagger + CGFloat(column) * scale, y: y)
                var arc = Path()
                arc.addArc(
                    center: CGPoint(x: origin.x + scale / 2, y: origin.y + scale / 2),
                    radius: scale / 2,
                    startAngle: .degrees(0),
                    endAngle: .degrees(180),
                    clockwise: false
                )
                clipped.stroke(arc, with: .color(ink), lineWidth: 0.7)
            }
        }
    }
}
