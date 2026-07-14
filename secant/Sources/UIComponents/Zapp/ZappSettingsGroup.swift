//
//  ZappSettingsGroup.swift
//  Zapp
//

import SwiftUI

/// A titled, bordered settings group shared by the You and Chat Profile surfaces.
struct ZappSettingsGroup<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            ZappGroupHeader(text: title)

            VStack(spacing: 0) {
                content
            }
            .background(ZappColors.surface.color(colorScheme))
            .overlay(
                Rectangle()
                    .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
            )
            .padding(.horizontal, 14)

            Spacer()
                .frame(height: Design.Spacing._md)
        }
    }
}
