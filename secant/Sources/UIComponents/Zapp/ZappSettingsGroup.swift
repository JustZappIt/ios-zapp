//
//  ZappSettingsGroup.swift
//  Zapp
//

import SwiftUI

/// A titled, bordered settings group shared by the You and Chat Profile surfaces.
struct ZappSettingsGroup<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    var titleLogo: Image?
    /// Read out in place of the title when the header is the logo alone.
    var titleLogoLabel: String?
    /// A muted caption under the box, as Android's `footer`.
    var footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            if let titleLogo {
                // Logo first, then the label, as Android's `ZappSettingsGroup` row.
                HStack(spacing: 8) {
                    titleLogo
                        .resizable()
                        .scaledToFit()
                        .frame(height: title.isEmpty ? 18 : 14)
                        .accessibilityLabel(titleLogoLabel ?? title)
                    if !title.isEmpty {
                        ZappSectionLabel(text: title)
                            .fixedSize()
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, ZappSettingsGroupLayout.textGutter)
                .padding(.top, 16)
                .padding(.bottom, 6)
                .padding(.trailing, ZappSettingsGroupLayout.textGutter)
            } else {
                ZappGroupHeader(text: title)
            }

            VStack(spacing: 0) {
                content
            }
            .background(ZappColors.surface.color(colorScheme))
            .overlay(
                Rectangle()
                    .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
            )
            .padding(.horizontal, 14)

            if let footer {
                Text(footer)
                    .zappFont(.caption, style: ZappColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, ZappSettingsGroupLayout.textGutter)
                    .padding(.top, Design.Spacing._md)
            }
        }
    }
}

private enum ZappSettingsGroupLayout {
    /// The header's text gutter, so the footer lines up with the title.
    static let textGutter: CGFloat = 18
}
