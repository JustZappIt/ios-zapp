// SPDX-License-Identifier: MIT OR Apache-2.0

import SwiftUI

/// A tappable explanation for a row's number. One type rather than two optional parameters: a
/// handler without a label ships an unlabelled button, and the pair is only ever correct together.
struct ZappSummaryRowInfo {
    let accessibilityLabel: String
    let action: () -> Void
}

struct ZappSummaryRow: View {
    private enum Constants {
        /// Small enough to sit on a caption line; the tap target is the overflow below.
        static let infoIconSize: CGFloat = 14
        static let infoTouchTarget: CGFloat = 44
        static let infoTouchInset: CGFloat = -(infoTouchTarget - infoIconSize) / 2
        static let labelIconGap: CGFloat = 2
        static let valueGap: CGFloat = 10
        static let valueStyle = ZappTextStyle(weight: .semiBold, size: 14, lineHeight: 20)
    }

    let label: String
    let value: String
    /// Set only where the row's number is one the user can act on — the tap has to lead somewhere,
    /// or the icon is a promise the row does not keep.
    var info: ZappSummaryRowInfo?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Constants.labelIconGap) {
                Text(label).zappFont(.caption, style: ZappColors.textMuted)

                if let info {
                    Button(action: info.action) {
                        Asset.Assets.infoCircle.image
                            .zImage(
                                width: Constants.infoIconSize,
                                height: Constants.infoIconSize,
                                style: ZappColors.textMuted
                            )
                            // The row is a caption line, so the icon stays small and the 44pt
                            // target overflows it rather than setting the row's height.
                            .contentShape(
                                Rectangle()
                                    .size(width: Constants.infoTouchTarget, height: Constants.infoTouchTarget)
                                    .offset(x: Constants.infoTouchInset, y: Constants.infoTouchInset)
                            )
                    }
                    .buttonStyle(.zappHighlight)
                    .accessibilityLabel(info.accessibilityLabel)
                }
            }
            Spacer(minLength: Constants.valueGap)
            // The emphasised half, on one line: it ellipsizes rather than wrapping so a long value
            // cannot push the label off the row (Android's `ZappSummaryRow`).
            Text(value)
                .zappFont(Constants.valueStyle, style: ZappColors.text)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

struct ZappBorderedCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    enum Variant { case standard, danger }

    let variant: Variant
    let padding: CGFloat
    let content: Content

    /// 14 is Android's `ZappBorderedCard` default; a few screens pass their own.
    init(variant: Variant = .standard, padding: CGFloat = 14, @ViewBuilder content: () -> Content) {
        self.variant = variant
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ZappColors.surface.color(colorScheme))
            .overlay(Rectangle().strokeBorder(border.color(colorScheme), lineWidth: 1))
    }

    private var border: ZappColors { variant == .danger ? .danger : .border }
}

/// Compact accent action for dense balance and summary rows, as Android's `ZappCompactButton`: a
/// small filled chip inside a 48pt touch target.
struct ZappCompactButton: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let horizontalPadding: CGFloat = 12
        static let verticalPadding: CGFloat = 6
        static let touchTarget: CGFloat = 48
    }

    let title: String
    /// Kept for source compatibility; Android's compact button has a single, accent style.
    var variant: ZappButtonVariant = .primary
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .zappFont(.buttonSmall, style: isEnabled ? ZappColors.onAccent : ZappColors.textSubtle)
                .lineLimit(1)
                .padding(.horizontal, Constants.horizontalPadding)
                .padding(.vertical, Constants.verticalPadding)
                .background((isEnabled ? ZappColors.accent : ZappColors.surfaceAlt).color(colorScheme))
                .frame(minHeight: Constants.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(!isEnabled)
        .accessibilityLabel(title)
    }
}

/// Ellipsized, tappable monospace link to a block explorer, in the accent and underlined as
/// Android's `ZappExplorerLink`.
struct ZappExplorerLink: View {
    let address: String
    let url: URL?

    var body: some View {
        Group {
            if let url {
                Link(destination: url) {
                    Text(address)
                        .underline()
                        .zappFont(.mono, style: ZappColors.accent)
                }
            } else {
                Text(address)
                    .zappFont(.mono, style: ZappColors.text)
            }
        }
        .lineLimit(1)
        .truncationMode(.middle)
    }
}

/// The balance beside an amount field, as Android's `ZappFieldBalance` carries it.
struct ZappFieldBalance: Equatable {
    let label: String
    let amount: String
}

/// The big amount entry for money flows, as Android's `ZappOfframpHeroAmountField`: no box, the
/// symbol and digits set in `display`, a 2pt accent rule underneath (danger on error), the balance
/// in a column at the trailing edge and an optional secondary line below the rule.
struct ZappAmountHero: View {
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isAmountFocused: Bool

    private enum Constants {
        static let labelGap: CGFloat = 14
        static let flagSize = CGSize(width: 30, height: 20)
        static let flagGap: CGFloat = 10
        static let symbolGap: CGFloat = 8
        static let balanceGap: CGFloat = 12
        static let fieldVerticalPadding: CGFloat = 4
        static let underline: CGFloat = 2
        static let secondaryGap: CGFloat = 8
        static let secondaryInset: CGFloat = 2
        static let heroStyle = ZappTextStyle(weight: .semiBold, size: 32, lineHeight: 36, tracking: -1.0)
        static let balanceAmountStyle = ZappTextStyle(weight: .medium, size: 12, lineHeight: 16)
    }

    let label: String
    let symbol: String
    let amount: String
    let balance: ZappFieldBalance?
    let isEnabled: Bool
    var isError = false
    var flag: Image?
    var secondary: String?
    let onChange: @Sendable (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.labelGap) {
            Text(label).zappFont(.eyebrow, style: ZappColors.textMuted)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 0) {
                    if let flag {
                        flag
                            .resizable()
                            .scaledToFit()
                            .frame(width: Constants.flagSize.width, height: Constants.flagSize.height)
                            .padding(.trailing, Constants.flagGap)
                            .accessibilityHidden(true)
                    }

                    Text(symbol)
                        .zappFont(Constants.heroStyle, style: ZappColors.text)
                        .padding(.trailing, Constants.symbolGap)

                    TextField("", text: Binding(get: { amount }, set: onChange))
                        .focused($isAmountFocused)
                        .keyboardType(.decimalPad)
                        .zappFont(Constants.heroStyle, style: isError ? ZappColors.danger : ZappColors.text)
                        .padding(.vertical, Constants.fieldVerticalPadding)
                        .disabled(!isEnabled)
                        .accessibilityLabel(label)

                    if let balance {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(balance.label).zappFont(.caption, style: ZappColors.textSubtle)
                            Text(balance.amount).zappFont(Constants.balanceAmountStyle, style: ZappColors.textMuted)
                        }
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.leading, Constants.balanceGap)
                        .accessibilityElement(children: .combine)
                    }
                }

                Rectangle()
                    .fill((isError ? ZappColors.danger : ZappColors.accent).color(colorScheme))
                    .frame(height: Constants.underline)

                if let secondary {
                    Text(secondary)
                        .zappFont(.body, style: ZappColors.textMuted)
                        .padding(.top, Constants.secondaryGap)
                        .padding(.leading, Constants.secondaryInset)
                }
            }
            .zappFieldTapTarget($isAmountFocused)
        }
    }
}
