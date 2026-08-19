// SPDX-License-Identifier: MIT OR Apache-2.0

import SwiftUI

/// Range chips for a chart, packed against the trailing edge — the port of Android's `PeriodSelector`
/// (`WalletBalanceCard.kt`), which arranges its chips with `Alignment.End`. Distinct from
/// `ZappSegmentedSelector`, which fills its width and reads as a control the eye has to parse; these
/// are a quiet caption under the chart.
struct ZappChartPeriodSelector: View {
    @Environment(\.colorScheme)
    private var colorScheme

    private enum Constants {
        static let chipHeight: CGFloat = 32
        static let chipMinWidth: CGFloat = 40
        /// Lifts the 32pt chip to the 44pt HIG target without growing the row.
        static let hitSlop: CGFloat = 6
    }

    let options: [String]
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: Design.Spacing._xxs) {
            Spacer(minLength: 0)

            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                chip(index, option)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .contain)
    }

    private func chip(_ index: Int, _ option: String) -> some View {
        let isSelected = index == selectedIndex

        return Button {
            onSelect(index)
        } label: {
            Text(option)
                .zappFont(.groupLabel, style: isSelected ? ZappColors.accentText : ZappColors.textSubtle)
                .padding(.horizontal, Design.Spacing._md)
                .frame(minWidth: Constants.chipMinWidth, minHeight: Constants.chipHeight)
                .background(isSelected ? ZappColors.accentSoft.color(colorScheme) : .clear)
                .padding(.vertical, Constants.hitSlop)
                .contentShape(Rectangle())
                .padding(.vertical, -Constants.hitSlop)
        }
        // Android passes `indication = null` here, so the press scale would be an addition, not a port.
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    VStack(spacing: 24) {
        ZappChartPeriodSelector(options: ["1w", "1m", "1y", "All"], selectedIndex: 0) { _ in }
        ZappChartPeriodSelector(options: ["1w", "1m", "1y", "All"], selectedIndex: 3) { _ in }
    }
    .padding()
    .applyScreenBackground()
}
