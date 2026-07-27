//
//  ZappScrollEdge.swift
//  Zapp
//
//  Appendix C.5: scroll-edge effects and a nav-pill shadow that reacts to scrolling.
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
//  The pill's shadow does need a scroll signal, since the pill floats above the content rather
//  than docking to it: `zappScrollShadowSource()` publishes how far its scroll view has travelled
//  and `ZappTabsView` feeds that to `ZappPillNavBar.elevation`.
//

import SwiftUI

enum ZappScrollEdge {
    /// Height of the colour ramp at each edge. Roughly one row's leading, so a row passing under
    /// it dissolves over its own height instead of blinking out.
    static let fadeHeight: CGFloat = 24

    /// Scroll distance over which the pill's shadow reaches full strength.
    static let shadowRampDistance: CGFloat = 24

    /// Named coordinate space a scroll view installs so its content can measure its own travel.
    static let coordinateSpace = "zappScrollEdge"
}

/// How far the tab's scroll view has travelled from the top, in points. `max` on reduce so the
/// one scrolling tab wins over any inert sibling reporting zero.
struct ZappScrollProgressKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ZappScrollEdgeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let edges: Edge.Set
    let color: ZappColors

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: ZappScrollEdge.coordinateSpace)
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

/// Reports the enclosing scroll view's travel without changing its layout.
private struct ZappScrollProbe: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: ZappScrollProgressKey.self,
                    value: max(0, -proxy.frame(in: .named(ZappScrollEdge.coordinateSpace)).minY)
                )
        }
    }
}

extension View {
    /// Applied to a `ScrollView`. Fades its content out at the named edges.
    func zappScrollEdges(_ edges: Edge.Set = [.top, .bottom], color: ZappColors = .bg) -> some View {
        modifier(ZappScrollEdgeModifier(edges: edges, color: color))
    }

    /// Applied to the CONTENT inside a `zappScrollEdges` scroll view, so the pill above it knows
    /// whether anything is passing underneath.
    func zappScrollShadowSource() -> some View {
        background(ZappScrollProbe())
    }
}
