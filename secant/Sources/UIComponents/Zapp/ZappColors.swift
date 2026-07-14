//
//  ZappColors.swift
//  Zapp
//

import SwiftUI

/// The Zapp palette, mirroring `ZappPalette.kt` token-for-token.
///
/// This is the fork's visual source of truth and it sits alongside `Design.*` (the upstream Zashi
/// layer) exactly as `ZappTheme.colors` sits alongside `ZashiColors` on Android: new Zapp components
/// read `ZappColors`, upstream screens keep reading `Design`.
enum ZappColors: Colorable {
    case bg
    case surface
    case surfaceAlt
    case surfaceInput
    case border
    case borderStrong
    case text
    case textMuted
    case textSubtle
    case accent
    case accentSoft
    case accentText
    case success
    case successSoft
    case danger
    case dangerSoft
    case chipBg
    case overlay
    case navPill
    case onAccent
    case shadow

    func color(_ colorScheme: ColorScheme) -> Color {
        let palette = colorScheme == .light ? ZappPalette.light : ZappPalette.dark

        switch self {
        case .bg: return palette.bg
        case .surface: return palette.surface
        case .surfaceAlt: return palette.surfaceAlt
        case .surfaceInput: return palette.surfaceInput
        case .border: return palette.border
        case .borderStrong: return palette.borderStrong
        case .text: return palette.text
        case .textMuted: return palette.textMuted
        case .textSubtle: return palette.textSubtle
        case .accent: return palette.accent
        case .accentSoft: return palette.accentSoft
        case .accentText: return palette.accentText
        case .success: return palette.success
        case .successSoft: return palette.successSoft
        case .danger: return palette.danger
        case .dangerSoft: return palette.dangerSoft
        case .chipBg: return palette.chipBg
        case .overlay: return palette.overlay
        case .navPill: return palette.navPill
        case .onAccent: return palette.onAccent
        case .shadow: return palette.shadow
        }
    }
}

struct ZappPalette {
    let bg: Color
    let surface: Color
    let surfaceAlt: Color
    let surfaceInput: Color
    let border: Color
    let borderStrong: Color
    let text: Color
    let textMuted: Color
    let textSubtle: Color
    let accent: Color
    let accentSoft: Color
    let accentText: Color
    let success: Color
    let successSoft: Color
    let danger: Color
    let dangerSoft: Color
    let chipBg: Color
    let overlay: Color
    let navPill: Color
    let onAccent: Color
    let shadow: Color
}

extension ZappPalette {
    // `onAccent` is white on #FF9417 (2.21:1, below WCAG AA). Android ships this; it is a brand
    // decision, replicated deliberately rather than silently corrected.
    static let light = ZappPalette(
        bg: Color(zappHex: 0xFFFF_FFFF),
        surface: Color(zappHex: 0xFFFF_FFFF),
        surfaceAlt: Color(zappHex: 0xFFF4_F2EE),
        surfaceInput: Color(zappHex: 0xFFF6_F4F0),
        border: Color(zappHex: 0xFFEB_E7E0),
        borderStrong: Color(zappHex: 0xFFD9_D4CA),
        text: Color(zappHex: 0xFF15_120D),
        textMuted: Color(zappHex: 0xFF6B_645A),
        textSubtle: Color(zappHex: 0xFF9A_9288),
        accent: Color(zappHex: 0xFFFF_9417),
        accentSoft: Color(zappHex: 0xFFFF_E7CC),
        accentText: Color(zappHex: 0xFFA6_5500),
        success: Color(zappHex: 0xFF2F_9D6A),
        successSoft: Color(zappHex: 0xFFD7_F0E3),
        danger: Color(zappHex: 0xFFD9_4545),
        dangerSoft: Color(zappHex: 0xFFFD_E2E0),
        chipBg: Color(zappHex: 0xFFEF_ECE5),
        overlay: Color(zappHex: 0x7314_1210),
        navPill: Color(zappHex: 0xFFEC_EBE5),
        onAccent: Color(zappHex: 0xFFFF_FFFF),
        shadow: Color(zappHex: 0x1414_1210)
    )

    static let dark = ZappPalette(
        bg: Color(zappHex: 0xFF0F_0E0C),
        surface: Color(zappHex: 0xFF17_1512),
        surfaceAlt: Color(zappHex: 0xFF1B_1916),
        surfaceInput: Color(zappHex: 0xFF20_1D19),
        border: Color(zappHex: 0xFF2A_2622),
        borderStrong: Color(zappHex: 0xFF3A_342D),
        text: Color(zappHex: 0xFFF6_F2EA),
        textMuted: Color(zappHex: 0xFFA5_9C90),
        textSubtle: Color(zappHex: 0xFF72_6A60),
        accent: Color(zappHex: 0xFFFF_9417),
        accentSoft: Color(zappHex: 0xFF3A_2713),
        accentText: Color(zappHex: 0xFFFF_B26B),
        success: Color(zappHex: 0xFF5F_D49C),
        successSoft: Color(zappHex: 0xFF1A_2E24),
        danger: Color(zappHex: 0xFFEF_6A5F),
        dangerSoft: Color(zappHex: 0xFF2E_1A18),
        chipBg: Color(zappHex: 0xFF1F_1C18),
        overlay: Color(zappHex: 0x8C00_0000),
        navPill: Color(zappHex: 0xFF1C_1A16),
        onAccent: Color(zappHex: 0xFF1A_140B),
        shadow: Color(zappHex: 0x8000_0000)
    )
}

extension Color {
    /// Takes Android's `AARRGGBB` literal so the palette ports across as a straight copy.
    init(zappHex: UInt32) {
        self.init(
            .sRGB,
            red: Double((zappHex >> 16) & 0xFF) / 255,
            green: Double((zappHex >> 8) & 0xFF) / 255,
            blue: Double(zappHex & 0xFF) / 255,
            opacity: Double((zappHex >> 24) & 0xFF) / 255
        )
    }
}
