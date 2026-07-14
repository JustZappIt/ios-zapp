//
//  ZappActionTile.swift
//  Zapp
//

import SwiftUI

/// Flat, bordered tile that stacks an icon tile over a label. Used in row layouts
/// (Send / Receive / Scan) where each tile takes equal weight.
struct ZappActionTile: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let minHeight: CGFloat = 96
        static let verticalPadding: CGFloat = 14
        static let iconBoxSize: CGFloat = 36
        static let iconSize: CGFloat = 18
        static let spacing: CGFloat = 10
        static let disabledOpacity: CGFloat = 0.45
    }

    let label: String
    let icon: Image
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Constants.spacing) {
                icon
                    .zImage(width: Constants.iconSize, height: Constants.iconSize, style: ZappColors.accentText)
                    .frame(width: Constants.iconBoxSize, height: Constants.iconBoxSize)
                    .background(ZappColors.accentSoft.color(colorScheme))

                Text(label)
                    .zappFont(.rowTitle, style: ZappColors.text)
            }
            .padding(.vertical, Constants.verticalPadding)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Constants.minHeight)
            .background(ZappColors.surface.color(colorScheme))
            .overlay(
                Rectangle()
                    .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : Constants.disabledOpacity)
        }
        .buttonStyle(.zappPress)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}

#Preview {
    HStack(spacing: 8) {
        ZappActionTile(label: "Receive", icon: Asset.Assets.Icons.arrowDown.image) { }
        ZappActionTile(label: "Send", icon: Asset.Assets.Icons.arrowUp.image) { }
        ZappActionTile(label: "Swap", icon: Asset.Assets.Icons.swapArrows.image, isEnabled: false) { }
    }
    .padding()
    .applyScreenBackground()
}
