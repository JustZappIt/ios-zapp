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
        static let iconSize: CGFloat = 16
        static let iconGap: CGFloat = 6
        /// Desaturated rather than faded: a yellow wordmark at low alpha on white disappears.
        static let unselectedLogoOpacity: Double = 0.75
    }

    let options: [String]
    /// A mark drawn in place of the label, keyed by index. The label stays as the accessibility
    /// name, so a logo segment is still announced.
    var logos: [Int: Image] = [:]
    /// A mark drawn *beside* the label, unlike `logos`, which replace it.
    var icons: [Int: Image] = [:]
    /// Visible cell height. The default is the compact size; taller for selectors that sit in a
    /// column of 52pt controls.
    var cellMinHeight: CGFloat = Constants.cellMinHeight
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
                    mark(logo, height: Constants.logoHeight, isSelected: isSelected)
                } else if let icon = icons[index] {
                    HStack(spacing: Constants.iconGap) {
                        mark(icon, height: Constants.iconSize, isSelected: isSelected)
                        label(option, isSelected: isSelected)
                    }
                } else {
                    label(option, isSelected: isSelected)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: cellMinHeight)
            .background(isSelected ? ZappColors.bg.color(colorScheme) : .clear)
            .padding(.vertical, Constants.hitSlop)
            .contentShape(Rectangle())
            .padding(.vertical, -Constants.hitSlop)
        }
        .buttonStyle(.zappPress)
        .accessibilityLabel(option)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func mark(_ image: Image, height: CGFloat, isSelected: Bool) -> some View {
        image
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .grayscale(isSelected ? 0 : 1)
            .opacity(isSelected ? 1 : Constants.unselectedLogoOpacity)
    }

    private func label(_ option: String, isSelected: Bool) -> some View {
        Text(option)
            .zappFont(.caption, style: isSelected ? ZappColors.text : ZappColors.textMuted)
            .lineLimit(1)
    }
}

#Preview {
    VStack(spacing: 20) {
        ZappSegmentedSelector(options: ["1D", "1W", "1M", "1Y"], selectedIndex: 1) { _ in }

        ZappSegmentedSelector(
            options: ["Zcash", "Base"],
            icons: [0: Asset.Assets.Assets.zec.image, 1: Asset.Assets.Assets.usdc.image],
            selectedIndex: 0
        ) { _ in }
    }
    .padding()
    .applyScreenBackground()
}
