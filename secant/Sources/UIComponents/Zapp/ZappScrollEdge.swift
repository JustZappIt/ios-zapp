//
//  ZappScrollEdge.swift
//  Zapp
//
//  Appendix C.5: scroll-edge effects.
//
//  Deliberately material-free. This is a Swiss-design app — sharp rectangles, flat fills, no
//  blur and no glass — so the edge effect is NOT a `.ultraThinMaterial` bar. It is a short ramp
//  of the screen's own background colour down to clear. Two consequences make that the right
//  primitive rather than a compromise:
//
//  - Over empty space it is invisible by construction (background over background), so a list
//    that does not fill its viewport shows nothing at all and needs no scroll tracking to hide it.
//  - Over content it reads as the row dissolving into the edge, the same way ink runs out on the
//    page, rather than as a translucent pane laid on top of it.
//
//  The nav pill's shadow used to ramp with scroll as well; it is now static, as Android's
//  `shadow(4.dp)`, so `zappScrollShadowSource()` no longer measures anything.
//

import SwiftUI

enum ZappScrollEdge {
    /// Height of the colour ramp at each edge. Roughly one row's leading, so a row passing under
    /// it dissolves over its own height instead of blinking out.
    static let fadeHeight: CGFloat = 24
}

private struct ZappScrollEdgeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let edges: Edge.Set
    let color: ZappColors

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if edges.contains(.top) {
                    ramp(startPoint: .top, endPoint: .bottom)
                }
            }
            .overlay(alignment: .bottom) {
                if edges.contains(.bottom) {
                    ramp(startPoint: .bottom, endPoint: .top)
                }
            }
    }

    private func ramp(startPoint: UnitPoint, endPoint: UnitPoint) -> some View {
        LinearGradient(
            colors: [color.color(colorScheme), color.color(colorScheme).opacity(0)],
            startPoint: startPoint,
            endPoint: endPoint
        )
        .frame(height: ZappScrollEdge.fadeHeight)
        .allowsHitTesting(false)
    }
}

extension View {
    /// Applied to a `ScrollView`. Fades its content out at the named edges.
    func zappScrollEdges(_ edges: Edge.Set = [.top, .bottom], color: ZappColors = .bg) -> some View {
        modifier(ZappScrollEdgeModifier(edges: edges, color: color))
    }

    /// Inert: the pill shadow it fed is static now. Kept so the tab call sites (Pay, Chats, You)
    /// compile untouched; remove it together with them.
    func zappScrollShadowSource() -> some View {
        self
    }
}
