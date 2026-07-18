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
/// A screen with a primary CTA passes it through `primaryAction:` so the dock renders one row — back
/// left, CTA right, as on Android. With no CTA the dock stays chrome-free (`ZappBottomActionBar`
/// switches on `PrimaryAction.self == EmptyView.self`).
struct ZashiBackModifier<PrimaryAction: View>: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    let disabled: Bool
    let hidden: Bool
    let invertedColors: Bool
    let customDismiss: (() -> Void)?
    let primaryAction: PrimaryAction

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
                        backTint: invertedColors ? .bg : .text,
                        isBackEnabled: !disabled
                    ) {
                        primaryAction
                    }
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
            ZashiBackModifier<EmptyView>(
                disabled: disabled,
                hidden: hidden,
                invertedColors: invertedColors,
                customDismiss: customDismiss,
                primaryAction: EmptyView()
            )
        )
    }

    /// The dock with a CTA in it: back left, action right.
    ///
    /// `primaryAction` is deliberately NOT the last parameter. Swift binds a bare trailing closure to
    /// the LAST closure-typed argument, so putting the `@ViewBuilder` last would make every one of the
    /// 57 existing `zashiBack { ... }` call sites silently rebind their `customDismiss` into this slot
    /// — yielding a dock whose back button does nothing and whose CTA is the old dismiss closure.
    /// Keeping it here means the plain overload still wins for those call sites, untouched.
    func zashiBack<PrimaryAction: View>(
        _ disabled: Bool = false,
        hidden: Bool = false,
        invertedColors: Bool = false,
        @ViewBuilder primaryAction: () -> PrimaryAction,
        customDismiss: (() -> Void)? = nil
    ) -> some View {
        modifier(
            ZashiBackModifier(
                disabled: disabled,
                hidden: hidden,
                invertedColors: invertedColors,
                customDismiss: customDismiss,
                primaryAction: primaryAction()
            )
        )
    }

    /// Back-left with an optional CTA-right: screens whose CTA exists only in some states pass
    /// `hasPrimaryAction: false` for the rest and get a chrome-free back button, not an empty bar.
    @ViewBuilder
    func zashiBack<PrimaryAction: View>(
        hasPrimaryAction: Bool,
        _ disabled: Bool = false,
        hidden: Bool = false,
        invertedColors: Bool = false,
        @ViewBuilder primaryAction: () -> PrimaryAction,
        customDismiss: (() -> Void)? = nil
    ) -> some View {
        if hasPrimaryAction {
            zashiBack(disabled, hidden: hidden, invertedColors: invertedColors, primaryAction: primaryAction, customDismiss: customDismiss)
        } else {
            zashiBack(disabled, hidden: hidden, invertedColors: invertedColors, customDismiss: customDismiss)
        }
    }
}
