//
//  ZappCopyIconButton.swift
//  Zapp
//

import SwiftUI

/// Copy affordance for key/address cards; flips to a success check while `isCopied` holds.
/// Mirrors `ZappCopyIconButton.kt`.
struct ZappCopyIconButton: View {
    private enum Constants {
        static let touchTarget: CGFloat = 48
        static let iconSize: CGFloat = 20
    }

    let isCopied: Bool
    let accessibilityLabel: String
    var copiedAccessibilityLabel = String(localizable: .newChatCopied)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            (isCopied ? Asset.Assets.Icons.checkSolid.image : Asset.Assets.copy.image)
                .zImage(
                    width: Constants.iconSize,
                    height: Constants.iconSize,
                    style: isCopied ? ZappColors.success : ZappColors.textMuted
                )
                .frame(width: Constants.touchTarget, height: Constants.touchTarget)
        }
        .buttonStyle(.zappPress)
        .accessibilityLabel(isCopied ? copiedAccessibilityLabel : accessibilityLabel)
    }
}

#Preview {
    HStack(spacing: 20) {
        ZappCopyIconButton(isCopied: false, accessibilityLabel: "Copy address") { }
        ZappCopyIconButton(isCopied: true, accessibilityLabel: "Copy address") { }
    }
    .applyScreenBackground()
}
