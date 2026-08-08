//
//  ZappTypeSpecimen.swift
//  Zapp
//

import SwiftUI

/// Living reference for the Zapp type scale. Renders every token in `ZappTextStyle` next to its spec.
struct ZappTypeSpecimen: View {
    @Environment(\.colorScheme) private var colorScheme

    private static let paragraph = """
        Encrypt the messages and the money. This paragraph exists to prove that the lineHeight token \
        resolves to real leading between wrapped lines, not just a number parked in a struct.
        """

    private static let tokens: [(String, ZappTextStyle)] = [
        ("display", .display),
        ("displaySecondary", .displaySecondary),
        ("balanceDisplay", .balanceDisplay),
        ("balanceFraction", .balanceFraction),
        ("screenTitle", .screenTitle),
        ("sectionTitle", .sectionTitle),
        ("eyebrow", .eyebrow),
        ("groupLabel", .groupLabel),
        ("rowTitle", .rowTitle),
        ("rowSubtitle", .rowSubtitle),
        ("body", .body),
        ("caption", .caption),
        ("chip", .chip),
        ("button", .button),
        ("buttonSmall", .buttonSmall),
        ("mono", .mono)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Spacing._2xl) {
                Text("TYPE SCALE")
                    .zappFont(.eyebrow, style: Design.Text.tertiary)

                ForEach(Self.tokens, id: \.0) { name, type in
                    specimen(name, type)
                }

                VStack(alignment: .leading, spacing: Design.Spacing._sm) {
                    Text("MULTI-LINE")
                        .zappFont(.groupLabel, style: Design.Text.tertiary)

                    Text(Self.paragraph)
                        .zappFont(.body, style: Design.Text.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Design.Spacing._lg)
            .padding(.bottom, 80)
        }
        .applyScreenBackground()
    }

    private func specimen(_ name: String, _ type: ZappTextStyle) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            Text(name)
                .zappFont(.mono, style: Design.Text.support)

            Text("Encrypt the money")
                .zappFont(type, style: Design.Text.primary)

            Text(spec(type))
                .zappFont(.mono, style: Design.Text.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Design.Spacing._xs)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Design.Surfaces.strokeSecondary.color(colorScheme))
                .frame(height: 1)
        }
    }

    private func spec(_ type: ZappTextStyle) -> String {
        let tracking = type.tracking == 0
            ? "0"
            : String(format: "%+.1f", type.tracking)

        return "\(Int(type.size))/\(Int(type.lineHeight))  \(weightName(type.weight))  tracking \(tracking)"
    }

    private func weightName(_ weight: ZashiFontModifier.FontWeight) -> String {
        switch weight {
        case .bold: return "bold"
        case .semiBold: return "semibold"
        case .medium: return "medium"
        case .regular: return "regular"
        default: return "\(weight)"
        }
    }
}

#Preview {
    ZappTypeSpecimen()
        .onAppear { FontFamily.registerAllCustomFonts() }
}
