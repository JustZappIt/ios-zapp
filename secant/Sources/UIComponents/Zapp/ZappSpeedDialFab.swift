//
//  ZappSpeedDialFab.swift
//  Zapp
//
//  Ported from ZappSpeedDialFab.kt. Replaces the row of icon buttons the upstream
//  home screen carries.
//

import SwiftUI

struct ZappSpeedDialAction: Identifiable {
    let id: String
    let icon: Image
    let label: String
    let action: () -> Void

    init(id: String? = nil, icon: Image, label: String, action: @escaping () -> Void) {
        self.id = id ?? label
        self.icon = icon
        self.label = label
        self.action = action
    }
}

struct ZappSpeedDialFab: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let toggleSize: CGFloat = 56
        static let iconSize: CGFloat = 24
        static let stackSpacing: CGFloat = 12
        static let labelGap: CGFloat = 12
        static let labelHorizontalPadding: CGFloat = 12
        static let labelVerticalPadding: CGFloat = 8
        static let expandedRotation: Double = 45
    }

    let expandLabel: String
    let collapseLabel: String
    let actions: [ZappSpeedDialAction]
    var trailingPadding: CGFloat = 18
    var bottomPadding: CGFloat = 0

    @State private var isExpanded = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if isExpanded {
                ZappColors.overlay.color(colorScheme)
                    .ignoresSafeArea()
                    .onTapGesture { collapse() }
                    .transition(.opacity)
            }

            VStack(alignment: .trailing, spacing: Constants.stackSpacing) {
                if isExpanded {
                    ForEach(actions) { action in
                        row(action)
                    }
                }

                toggle
            }
            .padding(.trailing, trailingPadding)
            .padding(.bottom, bottomPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .animation(ZappMotion.content, value: isExpanded)
    }

    private func row(_ action: ZappSpeedDialAction) -> some View {
        HStack(spacing: Constants.labelGap) {
            Text(action.label)
                .zappFont(.rowTitle, style: ZappColors.text)
                .padding(.horizontal, Constants.labelHorizontalPadding)
                .padding(.vertical, Constants.labelVerticalPadding)
                .background(ZappColors.surface.color(colorScheme))

            ZappFab(icon: action.icon, accessibilityLabel: action.label) {
                // Collapse BEFORE firing: the action pushes a screen, and a speed dial
                // left open behind it reappears expanded when the user comes back.
                collapse()
                action.action()
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var toggle: some View {
        Button {
            isExpanded.toggle()
        } label: {
            Asset.Assets.Icons.plus.image
                .zImage(width: Constants.iconSize, height: Constants.iconSize, style: ZappColors.onAccent)
                .rotationEffect(.degrees(isExpanded ? Constants.expandedRotation : 0))
                .frame(width: Constants.toggleSize, height: Constants.toggleSize)
                .background(ZappColors.accent.color(colorScheme))
        }
        .buttonStyle(.zappPress)
        .accessibilityLabel(isExpanded ? collapseLabel : expandLabel)
    }

    private func collapse() {
        isExpanded = false
    }
}
