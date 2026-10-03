//
//  ZappFab.swift
//  Zapp
//

import SwiftUI

/// Flat orange square FAB, anchored above the floating nav pill.
struct ZappFab: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let size: CGFloat = 56
        static let iconSize: CGFloat = 24
    }

    let icon: Image
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            icon
                .zImage(width: Constants.iconSize, height: Constants.iconSize, style: ZappColors.onAccent)
                .frame(width: Constants.size, height: Constants.size)
                .background(ZappColors.accent.color(colorScheme))
                // Transparent in light; in dark it keeps the square's edge off the dark page.
                .overlay(Rectangle().strokeBorder(ZappColors.accentBorder.color(colorScheme), lineWidth: 1))
                .zappElevation()
        }
        .buttonStyle(.zappPress)
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview {
    ZappFab(icon: Asset.Assets.Icons.plus.image, accessibilityLabel: "New") { }
}
