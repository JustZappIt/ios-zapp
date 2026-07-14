//
//  ZappRow.swift
//  Zapp
//

import SwiftUI

struct ZappRow<Trailing: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    private typealias Constants = ZappRowConstants

    let title: String
    var subtitle: String?
    var icon: Image?
    var iconTint: ZappColors = .text
    var iconBackground: ZappColors = .surfaceAlt
    var titleColor: ZappColors = .text
    var action: (() -> Void)?

    private let trailing: Trailing

    /// `trailing` is deliberately NOT the final parameter: a bare trailing closure must bind to
    /// `action`, matching Kotlin, where `trailing` defaults to the chevron and `onClick` is last.
    init(
        title: String,
        subtitle: String? = nil,
        icon: Image? = nil,
        iconTint: ZappColors = .text,
        iconBackground: ZappColors = .surfaceAlt,
        titleColor: ZappColors = .text,
        @ViewBuilder trailing: () -> Trailing,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconTint = iconTint
        self.iconBackground = iconBackground
        self.titleColor = titleColor
        self.action = action
        self.trailing = trailing()
    }

    var body: some View {
        if let action {
            Button(action: action) { row }
                .buttonStyle(.zappPress)
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: Constants.spacing) {
            if let icon {
                icon
                    .zImage(width: Constants.iconSize, height: Constants.iconSize, style: iconTint)
                    .frame(width: Constants.iconBoxSize, height: Constants.iconBoxSize)
                    .background(iconBackground.color(colorScheme))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .zappFont(.rowTitle, style: titleColor)
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .zappFont(.rowSubtitle, style: ZappColors.textMuted)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.vertical, Constants.verticalPadding)
        .frame(maxWidth: .infinity)
        .frame(minHeight: Constants.minHeight)
        .contentShape(Rectangle())
    }
}

private enum ZappRowConstants {
    static let minHeight: CGFloat = 56
    static let horizontalPadding: CGFloat = 18
    static let verticalPadding: CGFloat = 12
    static let spacing: CGFloat = 14
    static let iconBoxSize: CGFloat = 36
    static let iconSize: CGFloat = 18
    static let trailingIconSize: CGFloat = 18
}

/// A chevron implies a tap target, so `action` is required — and, being non-optional, it is what a
/// bare trailing closure binds to. An optional closure is skipped by Swift's trailing-closure scan,
/// which would silently hand `{ }` to `trailing` and produce a dead, chevron-less row.
extension ZappRow where Trailing == ZappRowChevron {
    init(
        title: String,
        subtitle: String? = nil,
        icon: Image? = nil,
        iconTint: ZappColors = .text,
        iconBackground: ZappColors = .surfaceAlt,
        titleColor: ZappColors = .text,
        action: @escaping () -> Void
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            icon: icon,
            iconTint: iconTint,
            iconBackground: iconBackground,
            titleColor: titleColor,
            trailing: { ZappRowChevron() },
            action: action
        )
    }
}

struct ZappRowChevron: View {
    var body: some View {
        Asset.Assets.chevronRight.image
            .zImage(
                width: ZappRowConstants.trailingIconSize,
                height: ZappRowConstants.trailingIconSize,
                style: ZappColors.textSubtle
            )
    }
}

/// A `ZappRow` whose trailing slot reflects selection: a check when selected, nothing otherwise.
struct ZappSelectionRow: View {
    let title: String
    var subtitle: String?
    let isSelected: Bool
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        ZappRow(
            title: title,
            subtitle: subtitle,
            titleColor: titleColor,
            trailing: {
                if isEnabled && isSelected {
                    Asset.Assets.Icons.checkSolid.image
                        .zImage(
                            width: ZappRowConstants.trailingIconSize,
                            height: ZappRowConstants.trailingIconSize,
                            style: ZappColors.accentText
                        )
                }
            },
            action: isEnabled ? action : nil
        )
    }

    private var titleColor: ZappColors {
        if !isEnabled {
            return .textMuted
        }

        return isSelected ? .accentText : .text
    }
}

/// Hairline row divider, inset under the row title column when `inset` is true.
struct ZappRowDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var inset = false

    var body: some View {
        Rectangle()
            .fill(ZappColors.border.color(colorScheme))
            .frame(height: 1)
            .padding(.leading, inset ? 68 : 18)
            .padding(.trailing, 18)
    }
}

#Preview {
    VStack(spacing: 0) {
        ZappRow(title: "Chat profile", subtitle: "Display name, avatar") { }
        ZappRowDivider(inset: true)
        ZappSelectionRow(title: "Local currency", subtitle: "USD", isSelected: true) { }
        ZappRowDivider()
        ZappSelectionRow(title: "Disabled", subtitle: nil, isSelected: false, isEnabled: false) { }
    }
    .applyScreenBackground()
}
