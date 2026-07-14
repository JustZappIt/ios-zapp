//
//  ZashiFont.swift
//  Zashi
//
//  Created by Lukáš Korba on 09-16-2024
//

import SwiftUI
import UIKit.UIFont

struct ZashiFontModifier: ViewModifier {
    enum InternalFontFamily {
        case inter
        case michroma
        case robotoMono
    }
    
    enum FontWeight: Equatable {
        case black
        case blackItalic
        case bold
        case boldItalic
        case extraBold
        case extraBoldItalic
        case extraLight
        case extraLightItalic
        case italic
        case light
        case lightItalic
        case medium
        case mediumItalic
        case regular
        case semiBold
        case semiBoldItalic
        case thin
        case thinItalic
    }
    
    let weight: FontWeight
    let fontFamily: ZashiFontModifier.InternalFontFamily
    let size: CGFloat
    let color: Color?
    let style: Colorable?
    var tracking: CGFloat = 0
    var lineHeight: CGFloat?

    func body(content: Content) -> some View {
        if let color {
            content
                .font(.custom(font.name, size: size))
                .tracking(tracking)
                .lineSpacing(lineSpacing)
                .foregroundColor(color)
        } else if let style {
            content
                .font(.custom(font.name, size: size))
                .tracking(tracking)
                .lineSpacing(lineSpacing)
                .zForegroundColor(style)
        } else {
            EmptyView()
        }
    }

    /// SwiftUI has no line-height API: `lineSpacing` is additive leading *between* lines, so the
    /// Android `lineHeight` token has to be expressed as a delta over the font's natural line box.
    /// No-op on single-line text, which is most of the scale.
    private var lineSpacing: CGFloat {
        guard let lineHeight, let naturalLineHeight else { return 0 }

        return lineHeight - naturalLineHeight
    }

    private var naturalLineHeight: CGFloat? {
        // `UIFont(name:)` skips the family-name scan that the registering initializer pays for, but
        // it only resolves once `registerAllCustomFonts()` has run — which is not the case in previews.
        let resolved = UIFont(name: font.name, size: size) ?? UIFont(font: font, size: size)

        return resolved?.lineHeight
    }

    private var font: FontConvertible {
        fontConvertible(weight, fontFamily: fontFamily)
    }

    private func fontConvertible(
        _ weight: FontWeight,
        fontFamily: ZashiFontModifier.InternalFontFamily = .inter
    ) -> FontConvertible {
        if fontFamily == .robotoMono {
            switch weight {
            case .bold: return FontFamily.RobotoMono.bold
            case .medium: return FontFamily.RobotoMono.medium
            case .semiBold: return FontFamily.RobotoMono.semiBold
            default: return FontFamily.RobotoMono.regular
            }
        } else if fontFamily == .inter {
            switch weight {
            case .black: return FontFamily.Inter.black
            case .blackItalic: return FontFamily.Inter.blackItalic
            case .bold: return FontFamily.Inter.bold
            case .boldItalic: return FontFamily.Inter.boldItalic
            case .extraBold: return FontFamily.Inter.extraBold
            case .extraBoldItalic: return FontFamily.Inter.extraBoldItalic
            case .extraLight: return FontFamily.Inter.extraLight
            case .extraLightItalic: return FontFamily.Inter.extraLightItalic
            case .italic: return FontFamily.Inter.italic
            case .light: return FontFamily.Inter.light
            case .lightItalic: return FontFamily.Inter.lightItalic
            case .medium: return FontFamily.Inter.medium
            case .mediumItalic: return FontFamily.Inter.mediumItalic
            case .regular: return FontFamily.Inter.regular
            case .semiBold: return FontFamily.Inter.semiBold
            case .semiBoldItalic: return FontFamily.Inter.semiBoldItalic
            case .thin: return FontFamily.Inter.thin
            case .thinItalic: return FontFamily.Inter.thinItalic
            }
        } else {
            switch weight {
            case .regular: return FontFamily.Michroma.regular
            default: return FontFamily.Michroma.regular
            }
        }
    }
}

extension View {
    func zFont(
        _ weight: ZashiFontModifier.FontWeight = .regular,
        fontFamily: ZashiFontModifier.InternalFontFamily = .inter,
        size: CGFloat,
        tracking: CGFloat = 0,
        style: Colorable
    ) -> some View {
        self.modifier(
            ZashiFontModifier(
                weight: weight,
                fontFamily: fontFamily,
                size: size,
                color: nil,
                style: style,
                tracking: tracking
            )
        )
    }

    func zFont(
        _ weight: ZashiFontModifier.FontWeight = .regular,
        fontFamily: ZashiFontModifier.InternalFontFamily = .inter,
        size: CGFloat,
        tracking: CGFloat = 0,
        color: Color
    ) -> some View {
        self.modifier(
            ZashiFontModifier(
                weight: weight,
                fontFamily: fontFamily,
                size: size,
                color: color,
                style: nil,
                tracking: tracking
            )
        )
    }
}
