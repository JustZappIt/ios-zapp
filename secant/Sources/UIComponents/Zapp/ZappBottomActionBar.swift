//
//  ZappBottomActionBar.swift
//  Zapp
//

import SwiftUI

/// Bottom action bar for detail/sub-screens.
///
/// The back button is always on the LEFT (thumb-reachable). An optional primary action — typically a
/// `ZappButton` — sits on the RIGHT, aligned with it. The content row holds a 52pt min height (the
/// `ZappButton` height) so the bar measures the same with or without a primary action. The
/// surface/border panel chrome only appears when there is a primary action; a lone back button
/// renders chrome-free.
private enum ZappBottomActionBarConstants {
    static let minHeight: CGFloat = 52
    static let gutter: CGFloat = 18
    static let innerPadding: CGFloat = 12
    static let bottomMargin: CGFloat = 8
}

struct ZappBottomActionBar<PrimaryAction: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    private typealias Constants = ZappBottomActionBarConstants

    private let onBack: () -> Void
    private let primaryAction: PrimaryAction

    /// Chrome-free when there is no primary action, matching `ZappBottomActionBar.kt`.
    private var hasChrome: Bool { PrimaryAction.self != EmptyView.self }

    init(onBack: @escaping () -> Void, @ViewBuilder primaryAction: () -> PrimaryAction) {
        self.onBack = onBack
        self.primaryAction = primaryAction()
    }

    var body: some View {
        HStack(spacing: 0) {
            ZappBackButton(action: onBack)

            Spacer(minLength: 0)

            primaryAction
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: Constants.minHeight)
        // The inset + margin land OUTSIDE the background/border, so the full border stays visible
        // above the home indicator. SwiftUI applies modifiers inside-out, so this reads in reverse
        // of the Compose chain.
        .padding(Constants.innerPadding)
        .background {
            if hasChrome {
                Rectangle()
                    .fill(ZappColors.surface.color(colorScheme))
                    .overlay(
                        Rectangle()
                            .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
                    )
            }
        }
        .padding(.bottom, Constants.bottomMargin)
        .padding(.horizontal, Constants.gutter)
    }
}

extension ZappBottomActionBar where PrimaryAction == EmptyView {
    init(onBack: @escaping () -> Void) {
        self.init(onBack: onBack) { EmptyView() }
    }
}

#Preview {
    VStack(spacing: 40) {
        Spacer()

        ZappBottomActionBar(onBack: { })

        ZappBottomActionBar(onBack: { }) {
            ZappButton(title: "Continue") { }
        }
    }
    .applyScreenBackground()
}
