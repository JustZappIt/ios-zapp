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

extension View {
    /// Scrolls, and offers `.large`: explainer copy grows with translation and with Dynamic Type,
    /// and a fixed-height sheet clips it exactly the way the pinned-to-the-page version did.
    func zappInfoSheet(onDismiss: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            ScrollView { self }

            ZappButton(title: String(localizable: .peerFormInfoDismiss), action: onDismiss)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .applyScreenBackground()
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    ZappScreenHeader(title: "Payment method") {
        ZappInfoButton(accessibilityLabel: "How this works") { }
    }
    .applyScreenBackground()
}
