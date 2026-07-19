//
//  ZappAvatar.swift
//  Zashi
//
//  A circular initials avatar rendered on the Zapp brand gradient.
//

import SwiftUI

/// A circular avatar showing the first two characters of a display name,
/// uppercased on a vertical `primary -> accent` gradient with `onPrimary` text.
public struct ZappAvatar: View {
    private let name: String
    private let diameter: CGFloat

    public init(name: String, diameter: CGFloat = 72) {
        self.name = name
        self.diameter = diameter
    }

    private var initials: String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2)).uppercased()
    }

    public var body: some View {
        Text(initials)
            .font(.custom(FontFamily.Inter.semiBold.name, size: diameter * 0.4))
            .foregroundColor(Asset.Colors.Zapp.onPrimary.color)
            .frame(width: diameter, height: diameter)
            .background {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Asset.Colors.Zapp.primary.color,
                                Asset.Colors.Zapp.accent.color
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
    }
}
