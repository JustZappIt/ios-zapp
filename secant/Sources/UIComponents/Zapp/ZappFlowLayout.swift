//
//  ZappFlowLayout.swift
//  Zapp
//

import SwiftUI

/// Compose's `FlowRow`, which SwiftUI has no equivalent of: subviews are laid left to right and
/// wrapped onto a new line when the next one would not fit.
///
/// It exists for chip groups whose length is data-driven — a Peer rail offers eleven settlement
/// currencies — where an `HStack` clips the tail and a horizontal `ScrollView` hides it behind a
/// gesture nothing signals.
///
/// Purely structural: it reads no colour, type or spacing token, so it adds a layout to the system
/// without adding a second way to style anything.
struct ZappFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(within: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(within: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    /// One pass over the subviews, reused by both phases so measurement and placement can never
    /// disagree about where a line breaks.
    private func rows(within maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty && needed > maxWidth {
                rows.append(current)
                current = Row()
            }
            current.append(index: index, size: size, spacing: spacing)
        }

        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0

        mutating func append(index: Int, size: CGSize, spacing: CGFloat) {
            width += indices.isEmpty ? size.width : spacing + size.width
            height = max(height, size.height)
            indices.append(index)
        }
    }
}
