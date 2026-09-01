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
        static let logoHeight: CGFloat = 16
        /// Desaturated rather than faded: a yellow wordmark at low alpha on white disappears.
        static let unselectedLogoOpacity: Double = 0.75
    }

    let options: [String]
    /// A mark drawn in place of the label, keyed by index. The label stays as the accessibility
    /// name, so a logo segment is still announced.
    var logos: [Int: Image] = [:]
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
            Group {
                if let logo = logos[index] {
                    logo
                        .resizable()
                        .scaledToFit()
                        .frame(height: Constants.logoHeight)
                        .grayscale(isSelected ? 0 : 1)
                        .opacity(isSelected ? 1 : Constants.unselectedLogoOpacity)
                } else {
                    Text(option)
                        .zappFont(.caption, style: isSelected ? ZappColors.text : ZappColors.textMuted)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: Constants.cellMinHeight)
            .background(isSelected ? ZappColors.bg.color(colorScheme) : .clear)
            .padding(.vertical, Constants.hitSlop)
            .contentShape(Rectangle())
            .padding(.vertical, -Constants.hitSlop)
        }
        .buttonStyle(.zappPress)
        .accessibilityLabel(option)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    ZappSegmentedSelector(options: ["1D", "1W", "1M", "1Y"], selectedIndex: 1) { _ in }
        .padding()
        .applyScreenBackground()
}
