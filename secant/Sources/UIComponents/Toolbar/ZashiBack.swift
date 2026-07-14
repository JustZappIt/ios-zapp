//
//  ZashiBack.swift
//
//
//  Created by Lukáš Korba on 04.10.2023.
//

import SwiftUI

/// Zapp puts back at the BOTTOM-LEFT, in a dock, never in a top app bar.
///
/// Rewritten in place rather than replaced with a `zappBack()` of our own: upstream funnels all 57
/// screens through this one modifier, so overriding it here relocates every back button at once AND
/// makes any screen we later merge from upstream conform automatically. A parallel modifier would
/// leave newly-merged screens silently reintroducing a top-bar back button.
///
/// Screens that own a bottom CTA render it above this dock for now. Folding those into the dock's
/// `primaryAction` slot — one row, back left, CTA right, as on Android — is per-screen work.
struct ZashiBackModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    let disabled: Bool
    let hidden: Bool
    let invertedColors: Bool
    let customDismiss: (() -> Void)?

    func body(content: Content) -> some View {
        if hidden {
            content
                .navigationBarBackButtonHidden(true)
        } else {
            content
                .navigationBarBackButtonHidden(true)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ZappBottomActionBar(
                        onBack: {
                            if let customDismiss {
                                customDismiss()
                            } else {
                                dismiss()
                            }
                        },
                        backTint: invertedColors ? .bg : .text
                    )
                    .disabled(disabled)
                }
        }
    }
}

extension View {
    func zashiBack(
        _ disabled: Bool = false,
        hidden: Bool = false,
        invertedColors: Bool = false,
        customDismiss: (() -> Void)? = nil
    ) -> some View {
        modifier(
            ZashiBackModifier(
                disabled: disabled,
                hidden: hidden,
                invertedColors: invertedColors,
                customDismiss: customDismiss
            )
        )
    }
}
