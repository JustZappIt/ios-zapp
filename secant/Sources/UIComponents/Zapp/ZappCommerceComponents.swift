// SPDX-License-Identifier: MIT OR Apache-2.0

import SwiftUI

struct ZappSummaryRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).zappFont(.caption, style: ZappColors.textMuted)
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

/// The balance shown beside an amount field, as Android's `ZappFieldBalance` carries it: a caption
/// naming the balance and the figure itself, kept as two pieces so the field can stack them.
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
        // Two columns rather than three stacked rows: the field on the left, the balance stacked
        // on the right. Reads as a pair of labelled figures and keeps the box two rows tall.
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
