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
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            if let titleLogo {
                HStack(spacing: 8) {
                    if !title.isEmpty {
                        ZappGroupHeader(text: title)
                            .fixedSize()
                    }
                    titleLogo
                        .resizable()
                        .scaledToFit()
                        .frame(height: title.isEmpty ? 18 : 14)
                        .accessibilityLabel(titleLogoLabel ?? title)
                    Spacer(minLength: 0)
                }
                .padding(.leading, title.isEmpty ? 18 : 0)
                .padding(.top, title.isEmpty ? 16 : 0)
                .padding(.bottom, title.isEmpty ? 6 : 0)
                .padding(.trailing, 18)
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

            Spacer()
                .frame(height: Design.Spacing._md)
        }
    }
}
