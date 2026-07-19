//
//  ZappFAB.swift
//  Zashi
//
//  A circular floating action button in the Zapp style.
//

import SwiftUI

/// A 56pt circular floating action button filled with the Zapp primary colour,
/// an `onPrimary`-tinted icon, and the Zapp FAB shadow. The `alignment` lets
/// callers place it bottom-leading or bottom-trailing (hand preference).
public struct ZappFAB: View {
    private let icon: Image
    private let alignment: Alignment
    private let action: () -> Void

    private static let diameter: CGFloat = 56

    public init(
        icon: Image,
        alignment: Alignment = .bottomTrailing,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.alignment = alignment
        self.action = action
    }

    public var body: some View {
        Button {
            action()
        } label: {
            icon
                .renderingMode(.template)
                .foregroundColor(Asset.Colors.Zapp.onPrimary.color)
                .frame(width: Self.diameter, height: Self.diameter)
                .background {
                    Circle()
                        .fill(Asset.Colors.Zapp.primary.color)
                        .shadow(
                            color: Asset.Colors.Zapp.fabShadow.color,
                            radius: 8,
                            x: 0,
                            y: 4
                        )
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}
