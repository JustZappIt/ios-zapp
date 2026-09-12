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
    }

    let label: String
    let value: String
    /// Set only where the row's number is one the user can act on — the tap has to lead somewhere,
    /// or the icon is a promise the row does not keep.
    var info: ZappSummaryRowInfo?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
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
                    .buttonStyle(.zappPress)
                    .accessibilityLabel(info.accessibilityLabel)
                }
            }
            Spacer(minLength: 8)
            Text(value)
                .zappFont(.body, style: ZappColors.text)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct ZappBorderedCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    enum Variant { case standard, danger }

    let variant: Variant
    let content: Content

    init(variant: Variant = .standard, @ViewBuilder content: () -> Content) {
        self.variant = variant
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ZappColors.surface.color(colorScheme))
            .overlay(Rectangle().strokeBorder(border.color(colorScheme), lineWidth: 1))
    }

    private var border: ZappColors { variant == .danger ? .danger : .border }
}

struct ZappSuccessHeader: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Asset.Assets.check.image
                .zImage(size: 18, style: ZappColors.onAccent)
                .frame(width: 36, height: 36)
                .background(ZappColors.success.color(colorScheme))
            Text(title).zappFont(.screenTitle, style: ZappColors.text)
            Text(subtitle).zappFont(.body, style: ZappColors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ZappCompactButton: View {
    let title: String
    var variant: ZappButtonVariant = .ghost
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        ZappButton(title: title, variant: variant, isEnabled: isEnabled, action: action)
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct ZappExplorerLink: View {
    let address: String
    let url: URL?

    var body: some View {
        Group {
            if let url {
                Link(address, destination: url)
            } else {
                Text(address)
            }
        }
        .zappFont(.mono, style: ZappColors.text)
        .lineLimit(1)
        .truncationMode(.middle)
    }
}

/// The balance beside an amount field, as Android's `ZappFieldBalance` carries it.
struct ZappFieldBalance: Equatable {
    let label: String
    let amount: String
}

struct ZappAmountHero: View {
    @Environment(\.colorScheme) private var colorScheme

    let label: String
    let symbol: String
    let amount: String
    let balance: ZappFieldBalance?
    let isEnabled: Bool
    let onChange: @Sendable (String) -> Void

    var body: some View {
        // Two columns rather than three stacked rows, so the box stays two rows tall.
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(label).zappFont(.caption, style: ZappColors.textMuted)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(symbol).zappFont(.screenTitle, style: ZappColors.textMuted)
                    TextField("", text: Binding(get: { amount }, set: onChange))
                        .keyboardType(.decimalPad)
                        .zappFont(.screenTitle, style: ZappColors.text)
                        .disabled(!isEnabled)
                        .accessibilityLabel(label)
                }
            }

            if let balance {
                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 8) {
                    Text(balance.label).zappFont(.caption, style: ZappColors.textMuted)
                    Text(balance.amount).zappFont(.rowTitle, style: ZappColors.text)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .background(ZappColors.surface.color(colorScheme))
        .overlay(Rectangle().strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1))
    }
}
