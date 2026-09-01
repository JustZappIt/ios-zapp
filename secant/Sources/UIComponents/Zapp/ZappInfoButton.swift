// SPDX-License-Identifier: MIT OR Apache-2.0

import SwiftUI

/// The header's "what is this screen" affordance, where Android puts an explainer instead of
/// running it as prose down the page. Mirrors `InfoAction` in `PeerCashOutView.kt`.
struct ZappInfoButton: View {
    private enum Constants {
        static let touchTarget: CGFloat = 44
        static let iconSize: CGFloat = 20
    }

    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Asset.Assets.infoCircle.image
                .zImage(width: Constants.iconSize, height: Constants.iconSize, style: ZappColors.text)
                .frame(width: Constants.touchTarget, height: Constants.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.zappPress)
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview {
    ZappScreenHeader(title: "Payment method") {
        ZappInfoButton(accessibilityLabel: "How this works") { }
    }
    .applyScreenBackground()
}
