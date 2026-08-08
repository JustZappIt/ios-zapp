//
//  ZappAssetPill.swift
//  Zapp
//

import SwiftUI

/// Centered shielded-ZEC selector used by the direct-send form. Android uses
/// the same compact asset-card treatment for ZEC when no alternative asset is selectable.
struct ZappAssetPill: View {
    @Environment(\.colorScheme) private var colorScheme

    let tokenName: String

    var body: some View {
        HStack(spacing: 10) {
            Asset.Assets.Brandmarks.brandmarkMax.image
                .zImage(width: 24, height: 24, style: ZappColors.text)
                .overlay(alignment: .bottomTrailing) {
                    Asset.Assets.Icons.shieldTickFilled.image
                        .zImage(width: 11, height: 11, style: ZappColors.text)
                        .frame(width: 14, height: 14)
                        .background(ZappColors.surface.color(colorScheme))
                        .offset(x: 4, y: 4)
                }

            Text(tokenName.uppercased())
                .zappFont(.rowTitle, style: ZappColors.text)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(ZappColors.surface.color(colorScheme))
        .overlay {
            Rectangle()
                .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
