//
//  ZappCard.swift
//  Zashi
//
//  A rounded, elevated container that groups related content into a card,
//  mirroring the Android `SettingsCard`. Uses the Zapp design tokens and palette.
//

import SwiftUI

/// A rounded-rectangle card container filled with the Zapp tertiary background
/// and a subtle card shadow. Wraps arbitrary `content`.
public struct ZappCard<Content: View>: View {
    private let cornerRadius: CGFloat
    private let padding: CGFloat
    @ViewBuilder private let content: Content

    public init(
        cornerRadius: CGFloat = ZappDesign.Radius.medium,
        padding: CGFloat = ZappDesign.Spacing.base,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Asset.Colors.Zapp.tertiaryBackground.color)
                    .shadow(
                        color: Asset.Colors.Zapp.cardShadow.color,
                        radius: 8,
                        x: 0,
                        y: 2
                    )
            }
    }
}
