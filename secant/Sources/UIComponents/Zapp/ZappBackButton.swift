//
//  ZappBackButton.swift
//  Zapp
//

import SwiftUI

/// 48pt touch target (Google Play minimum, kept on iOS for parity). Visual arrow is 20pt, centered.
struct ZappBackButton: View {
    private enum Constants {
        static let touchTarget: CGFloat = 48
        static let iconSize: CGFloat = 20
    }

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Asset.Assets.Icons.arrowNarrowLeft.image
                .zImage(width: Constants.iconSize, height: Constants.iconSize, style: ZappColors.text)
                .frame(width: Constants.touchTarget, height: Constants.touchTarget)
        }
        .buttonStyle(.zappPress)
        .accessibilityLabel(String(localizable: .generalBack))
    }
}

#Preview {
    ZappBackButton { }
}
