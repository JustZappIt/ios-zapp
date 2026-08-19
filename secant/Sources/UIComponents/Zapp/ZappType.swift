//
//  ZappType.swift
//  Zapp
//

import SwiftUI

/// The Zapp type scale, mirroring `ZappTypography.kt` token-for-token. Android is the source of
/// truth: where `design-system.md` and the shipped Kotlin disagree, the Kotlin wins.
///
/// Two deliberate platform substitutions:
/// - family: Android ships `FontFamily.Default` (system sans); iOS keeps Inter (decision D4).
/// - `mono`: Android ships `FontFamily.Monospace`; iOS uses RobotoMono, the closest bundled face.
struct ZappTextStyle: Equatable {
    let family: ZashiFontModifier.InternalFontFamily
    let weight: ZashiFontModifier.FontWeight
    let size: CGFloat
    let lineHeight: CGFloat
    let tracking: CGFloat

    init(
        family: ZashiFontModifier.InternalFontFamily = .inter,
        weight: ZashiFontModifier.FontWeight,
        size: CGFloat,
        lineHeight: CGFloat,
        tracking: CGFloat = 0
    ) {
        self.family = family
        self.weight = weight
        self.size = size
        self.lineHeight = lineHeight
        self.tracking = tracking
    }
}

extension ZappTextStyle {
    static let pinHero = ZappTextStyle(weight: .black, size: 42, lineHeight: 44, tracking: -1.8)
    static let screenTitle = ZappTextStyle(weight: .bold, size: 22, lineHeight: 28, tracking: -0.5)
    static let sectionTitle = ZappTextStyle(weight: .bold, size: 18, lineHeight: 24, tracking: -0.3)
    static let display = ZappTextStyle(weight: .bold, size: 32, lineHeight: 36, tracking: -1.0)
    static let displaySecondary = ZappTextStyle(weight: .bold, size: 24, lineHeight: 28, tracking: -0.5)
    static let balanceDisplay = ZappTextStyle(weight: .black, size: 35.2, lineHeight: 39.6, tracking: -1.0)
    static let balanceFraction = ZappTextStyle(weight: .bold, size: 19.8, lineHeight: 26.4, tracking: -0.3)
    static let eyebrow = ZappTextStyle(weight: .bold, size: 11, lineHeight: 14, tracking: 1.0)
    static let groupLabel = ZappTextStyle(weight: .bold, size: 10, lineHeight: 14, tracking: 1.0)
    static let rowTitle = ZappTextStyle(weight: .semiBold, size: 15, lineHeight: 20)
    static let rowSubtitle = ZappTextStyle(weight: .regular, size: 13, lineHeight: 18)
    static let body = ZappTextStyle(weight: .regular, size: 14, lineHeight: 20)
    static let caption = ZappTextStyle(weight: .medium, size: 12, lineHeight: 16)
    static let chip = ZappTextStyle(weight: .semiBold, size: 11, lineHeight: 14, tracking: 0.4)
    static let button = ZappTextStyle(weight: .semiBold, size: 15, lineHeight: 20)
    static let buttonSmall = ZappTextStyle(weight: .semiBold, size: 12, lineHeight: 16)
    static let pinKey = ZappTextStyle(weight: .black, size: 20, lineHeight: 24)
    static let mono = ZappTextStyle(family: .robotoMono, weight: .medium, size: 12, lineHeight: 16)
}

extension View {
    func zappFont(_ type: ZappTextStyle, style: Colorable) -> some View {
        self.modifier(
            ZashiFontModifier(
                weight: type.weight,
                fontFamily: type.family,
                size: type.size,
                color: nil,
                style: style,
                tracking: type.tracking,
                lineHeight: type.lineHeight
            )
        )
    }

    func zappFont(_ type: ZappTextStyle, color: Color) -> some View {
        self.modifier(
            ZashiFontModifier(
                weight: type.weight,
                fontFamily: type.family,
                size: type.size,
                color: color,
                style: nil,
                tracking: type.tracking,
                lineHeight: type.lineHeight
            )
        )
    }
}
