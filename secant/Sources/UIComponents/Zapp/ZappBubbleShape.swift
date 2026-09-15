//
//  ZappBubbleShape.swift
//  Zapp
//

import SwiftUI

/// A message bubble: a lightly rounded box with a small tail on the side the message came
/// from, level with the last line. The tail is what marks the sender at a glance, and it only
/// reads as one shape on a softened box — the deliberate exception to the sharp-corner rule.
struct ZappBubbleShape: Shape {
    enum Tail {
        case leading
        case trailing
    }

    static let cornerRadius: CGFloat = 4
    static let tailDepth: CGFloat = 6
    static let tailHeight: CGFloat = 12
    /// The centre of a one-line body (12pt padding around 20pt of text). Anchoring here keeps
    /// the tail on the body of a quoted bubble instead of the seam with its quote band.
    static let tailAnchorFromBottom: CGFloat = 22

    let tail: Tail

    func path(in rect: CGRect) -> Path {
        let radius = Self.cornerRadius
        let depth = Self.tailDepth
        let halfTail = Self.tailHeight / 2
        let box = CGRect(
            x: tail == .leading ? rect.minX + depth : rect.minX,
            y: rect.minY,
            width: rect.width - depth,
            height: rect.height
        )
        let midY = box.maxY - min(box.height / 2, Self.tailAnchorFromBottom)

        var path = Path()
        path.move(to: CGPoint(x: box.minX + radius, y: box.minY))
        path.addLine(to: CGPoint(x: box.maxX - radius, y: box.minY))
        path.addArc(
            center: CGPoint(x: box.maxX - radius, y: box.minY + radius),
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        if tail == .trailing {
            path.addLine(to: CGPoint(x: box.maxX, y: midY - halfTail))
            path.addLine(to: CGPoint(x: rect.maxX, y: midY))
            path.addLine(to: CGPoint(x: box.maxX, y: midY + halfTail))
        }
        path.addLine(to: CGPoint(x: box.maxX, y: box.maxY - radius))
        path.addArc(
            center: CGPoint(x: box.maxX - radius, y: box.maxY - radius),
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: box.minX + radius, y: box.maxY))
        path.addArc(
            center: CGPoint(x: box.minX + radius, y: box.maxY - radius),
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        if tail == .leading {
            path.addLine(to: CGPoint(x: box.minX, y: midY + halfTail))
            path.addLine(to: CGPoint(x: rect.minX, y: midY))
            path.addLine(to: CGPoint(x: box.minX, y: midY - halfTail))
        }
        path.addLine(to: CGPoint(x: box.minX, y: box.minY + radius))
        path.addArc(
            center: CGPoint(x: box.minX + radius, y: box.minY + radius),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

extension View {
    /// Fills the view with a bubble whose tail points to `tail`, reserving the tail strip so
    /// the content never sits in it.
    func zappBubble(tail: ZappBubbleShape.Tail, fill: Color) -> some View {
        let shape = ZappBubbleShape(tail: tail)

        return self
            .padding(.leading, tail == .leading ? ZappBubbleShape.tailDepth : 0)
            .padding(.trailing, tail == .trailing ? ZappBubbleShape.tailDepth : 0)
            .background(fill, in: shape)
            .clipShape(shape)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        Text(verbatim: "yeah")
            .padding(12)
            .zappBubble(tail: .leading, fill: ZappColors.surfaceAlt.color(.dark))

        Text(verbatim: "on my way")
            .padding(12)
            .zappBubble(tail: .trailing, fill: ZappColors.accent.color(.dark))
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .padding(16)
    .applyScreenBackground()
    .preferredColorScheme(.dark)
}
