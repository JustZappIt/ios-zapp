//
//  ZappValueCard.swift
//  Zapp
//

import SwiftUI

/// Bordered card holding a monospaced value — a messaging key, a wallet address — with an optional
/// `label` above it, an explanatory `caption` underneath, and slots either side for a preview
/// (`leading`) and an action (`trailing`). Mirrors `ZappValueCard.kt`.
struct ZappValueCard<Leading: View, Trailing: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    private typealias Constants = ZappValueCardConstants

    let value: String
    var label: String?
    var caption: String?
    var lineLimit = Constants.defaultLineLimit

    private let leading: Leading
    private let trailing: Trailing

    init(
        value: String,
        label: String? = nil,
        caption: String? = nil,
        lineLimit: Int = Constants.defaultLineLimit,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.value = value
        self.label = label
        self.caption = caption
        self.lineLimit = lineLimit
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._md) {
            HStack(spacing: Constants.spacing) {
                leading

                VStack(alignment: .leading, spacing: Design.Spacing._xs) {
                    if let label {
                        Text(label)
                            .zappFont(.caption, style: ZappColors.textMuted)
                    }

                    Text(value)
                        .zappFont(.mono, style: ZappColors.text)
                        .lineLimit(lineLimit)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                trailing
            }
            .padding(Constants.cardPadding)
            .frame(maxWidth: .infinity)
            .background(ZappColors.surface.color(colorScheme))
            .overlay(
                Rectangle()
                    .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
            )
            .padding(.horizontal, Constants.gutter)

            if let caption {
                Text(caption)
                    .zappFont(.caption, style: ZappColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Constants.textGutter)
            }
        }
    }
}

private enum ZappValueCardConstants {
    static let defaultLineLimit = 3
    static let cardPadding: CGFloat = 14
    static let gutter: CGFloat = 14
    static let textGutter: CGFloat = 18
    static let spacing: CGFloat = 12
}

extension ZappValueCard where Leading == EmptyView {
    init(
        value: String,
        label: String? = nil,
        caption: String? = nil,
        lineLimit: Int = ZappValueCardConstants.defaultLineLimit,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(
            value: value,
            label: label,
            caption: caption,
            lineLimit: lineLimit,
            leading: { EmptyView() },
            trailing: trailing
        )
    }
}

extension ZappValueCard where Leading == EmptyView, Trailing == EmptyView {
    init(
        value: String,
        label: String? = nil,
        caption: String? = nil,
        lineLimit: Int = ZappValueCardConstants.defaultLineLimit
    ) {
        self.init(
            value: value,
            label: label,
            caption: caption,
            lineLimit: lineLimit,
            leading: { EmptyView() },
            trailing: { EmptyView() }
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        ZappValueCard(value: String(repeating: "a", count: 64), label: "Public key")

        ZappValueCard(
            value: "u1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq",
            label: "Shielded address",
            caption: "Private by default. Share this to receive shielded ZEC."
        ) {
            ZappCopyIconButton(isCopied: false, accessibilityLabel: "Copy address") { }
        }
    }
    .applyScreenBackground()
}
