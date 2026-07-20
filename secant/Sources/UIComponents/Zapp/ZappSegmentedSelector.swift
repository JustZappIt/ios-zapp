//
//  ZappSegmentedSelector.swift
//  Zapp
//

import SwiftUI

struct ZappSegmentedSelector: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let inset: CGFloat = 3
        static let spacing: CGFloat = 2
        static let cellMinHeight: CGFloat = 20
        static let hitSlop: CGFloat = 12
    }

    let options: [String]
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: Constants.spacing) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                cell(index, option)
            }
        }
        .padding(Constants.inset)
        .frame(maxWidth: .infinity)
        .background(ZappColors.surface.color(colorScheme))
        .overlay(
            Rectangle()
                .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
        )
    }

    private func cell(_ index: Int, _ option: String) -> some View {
        let isSelected = index == selectedIndex

        return Button {
            onSelect(index)
        } label: {
            Text(option)
                .zappFont(.caption, style: isSelected ? ZappColors.text : ZappColors.textMuted)
                .frame(maxWidth: .infinity)
                .frame(minHeight: Constants.cellMinHeight)
                .background(isSelected ? ZappColors.bg.color(colorScheme) : .clear)
                .padding(.vertical, Constants.hitSlop)
                .contentShape(Rectangle())
                .padding(.vertical, -Constants.hitSlop)
        }
        .buttonStyle(.zappPress)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    ZappSegmentedSelector(options: ["1D", "1W", "1M", "1Y"], selectedIndex: 1) { _ in }
        .padding()
        .applyScreenBackground()
}
