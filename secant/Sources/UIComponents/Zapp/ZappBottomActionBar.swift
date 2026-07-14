//
//  ZappBottomActionBar.swift
//  Zapp
//

import SwiftUI

/// Bottom action bar for detail/sub-screens.
///
/// The back button is always on the LEFT (thumb-reachable). An optional primary action — typically a
/// `ZappButton` — sits on the RIGHT inside the same bordered panel. A lone back button renders
/// chrome-free.
private enum ZappBottomActionBarConstants {
    static let minHeight: CGFloat = 52
    static let gutter: CGFloat = 18
    static let innerPadding: CGFloat = 12
    static let actionGap: CGFloat = 12
    static let bottomMargin: CGFloat = 8
}

struct ZappBottomActionBar<PrimaryAction: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    private typealias Constants = ZappBottomActionBarConstants

    private let onBack: () -> Void
    private let backTint: ZappColors
    private let primaryAction: PrimaryAction

    /// Chrome-free when there is no primary action, matching `ZappBottomActionBar.kt`.
    private var hasChrome: Bool { PrimaryAction.self != EmptyView.self }

    init(
        onBack: @escaping () -> Void,
        backTint: ZappColors = .text,
        @ViewBuilder primaryAction: () -> PrimaryAction
    ) {
        self.onBack = onBack
        self.backTint = backTint
        self.primaryAction = primaryAction()
    }

    @ViewBuilder
    var body: some View {
        if hasChrome {
            HStack(spacing: 0) {
                ZappBackButton(tint: backTint, action: onBack)

                primaryAction
                    .frame(maxWidth: .infinity)
                    .padding(.leading, Constants.actionGap)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: Constants.minHeight)
            .padding(Constants.innerPadding)
            .background(ZappColors.surface.color(colorScheme))
            .overlay(
                Rectangle()
                    .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
            )
            .padding(.bottom, Constants.bottomMargin)
            .padding(.horizontal, Constants.gutter)
        } else {
            HStack(spacing: 0) {
                ZappBackButton(tint: backTint, action: onBack)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: Constants.minHeight)
            .padding(.bottom, Constants.bottomMargin)
            .padding(.horizontal, Constants.gutter)
        }
    }
}

extension ZappBottomActionBar where PrimaryAction == EmptyView {
    init(onBack: @escaping () -> Void, backTint: ZappColors = .text) {
        self.init(onBack: onBack, backTint: backTint) { EmptyView() }
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
