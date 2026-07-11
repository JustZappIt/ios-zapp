//
//  ZappDesign.swift
//  Zapp
//
//  Zapp fork: iOS analog of android-zapp's `ZappTheme.colors` / `ZappNavBar` /
//  `ZappMotion`. Resolves the Zapp Swiss semantic tokens against the Phase 1
//  ZDesign color ramp so shell components can speak the same token names as
//  the Android spec (`c.bg`, `c.accent`, `c.onAccent`, ...).
//

import SwiftUI

/// Semantic Zapp Swiss colors, mirroring Android's `ZappTheme.colors` token table.
/// Every accessor resolves light/dark from the Phase 1 ZDesign ramp; tokens with no
/// exact colorset use the documented nearest ramp step (see docs/zapp-phase2-shell.md).
enum ZappColor {
    static func bg(_ scheme: ColorScheme) -> Color {
        col(Asset.Colors.ZDesign.Base.bone.color, Asset.Colors.ZDesign.Base.midnight.color, scheme)
    }

    /// Android `c.surface` (#FFFFFF / #171512): elements that sit on the page.
    static func surface(_ scheme: ColorScheme) -> Color {
        col(Asset.Colors.ZDesign.Base.bone.color, Asset.Colors.ZDesign.sharkShades01dp.color, scheme)
    }

    static func surfaceAlt(_ scheme: ColorScheme) -> Color {
        col(Asset.Colors.ZDesign.Base.concrete.color, Asset.Colors.ZDesign.shark900.color, scheme)
    }

    static func border(_ scheme: ColorScheme) -> Color {
        col(Asset.Colors.ZDesign.gray200.color, Asset.Colors.ZDesign.shark800.color, scheme)
    }

    static func text(_ scheme: ColorScheme) -> Color {
        col(Asset.Colors.ZDesign.Base.obsidian.color, Asset.Colors.ZDesign.shark50.color, scheme)
    }

    static func textMuted(_ scheme: ColorScheme) -> Color {
        col(Asset.Colors.ZDesign.gray600.color, Asset.Colors.ZDesign.shark400.color, scheme)
    }

    static func textSubtle(_ scheme: ColorScheme) -> Color {
        col(Asset.Colors.ZDesign.gray400.color, Asset.Colors.ZDesign.shark600.color, scheme)
    }

    static func accent(_ scheme: ColorScheme) -> Color {
        Asset.Colors.ZDesign.Base.brand.color
    }

    static func accentSoft(_ scheme: ColorScheme) -> Color {
        col(Asset.Colors.ZDesign.brand100.color, Asset.Colors.ZDesign.brand950.color, scheme)
    }

    static func accentText(_ scheme: ColorScheme) -> Color {
        col(Asset.Colors.ZDesign.brand700.color, Asset.Colors.ZDesign.brand300.color, scheme)
    }

    static func onAccent(_ scheme: ColorScheme) -> Color {
        col(Asset.Colors.ZDesign.Base.bone.color, Asset.Colors.ZDesign.Base.obsidian.color, scheme)
    }

    static func success(_ scheme: ColorScheme) -> Color {
        col(Asset.Colors.ZDesign.successGreen500.color, Asset.Colors.ZDesign.successGreen400.color, scheme)
    }

    static func successSoft(_ scheme: ColorScheme) -> Color {
        col(Asset.Colors.ZDesign.successGreen100.color, Asset.Colors.ZDesign.successGreen950.color, scheme)
    }

    static func danger(_ scheme: ColorScheme) -> Color {
        col(Asset.Colors.ZDesign.errorRed500.color, Asset.Colors.ZDesign.errorRed300.color, scheme)
    }

    static func dangerSoft(_ scheme: ColorScheme) -> Color {
        col(Asset.Colors.ZDesign.errorRed100.color, Asset.Colors.ZDesign.errorRed950.color, scheme)
    }

    /// Android `c.chipBg` (#EFECE5 / #1F1C18) - nearest ramp: Gray100 / SharkShades06dp.
    static func chipBg(_ scheme: ColorScheme) -> Color {
        col(Asset.Colors.ZDesign.gray100.color, Asset.Colors.ZDesign.sharkShades06dp.color, scheme)
    }

    /// Android `c.navPill` (#ECEBE5 / #1C1A16) - nearest ramp: Gray100 / Shark900.
    static func navPill(_ scheme: ColorScheme) -> Color {
        col(Asset.Colors.ZDesign.gray100.color, Asset.Colors.ZDesign.shark900.color, scheme)
    }

    /// Android `c.overlay`: modal scrims behind the expanded speed dial.
    static func overlay(_ scheme: ColorScheme) -> Color {
        col(Color.black.opacity(0.45), Color.black.opacity(0.55), scheme)
    }

    private static func col(_ light: Color, _ dark: Color, _ scheme: ColorScheme) -> Color {
        scheme == .dark ? dark : light
    }
}

/// Android `ZappNavBar` layout constants, mirrored 1:1 (dp treated as pt).
enum ZappNavBar {
    /// Bottom clearance for scrollable tab content above the floating pill.
    static let clearance: CGFloat = 80
    /// Bottom padding for FABs above the floating pill.
    static let fabBottomPadding: CGFloat = 80
}

/// Android `ZappMotion`: short, crisp tweens; no springs, no overshoot.
enum ZappMotion {
    /// Small state changes: color swaps, press feedback.
    static let state: Double = 0.12
    /// Content swaps: tab crossfade, step transitions.
    static let content: Double = 0.2
}
