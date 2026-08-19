//
//  ZappStatusChip.swift
//  Zapp
//

import SwiftUI

enum ZappChipVariant {
    case muted
    case success
    case accent
    case danger
    /// Bordered rather than filled: the compact ACTION treatment, not a status.
    case outlined
}

struct ZappStatusChip: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let horizontalPadding: CGFloat = 10
        static let verticalPadding: CGFloat = 4
        static let spacing: CGFloat = 6
        static let dotSize: CGFloat = 6
        static let iconSize: CGFloat = 12
        /// A tappable chip is ~22pt tall; padded out and given back to reach 44pt without resizing it.
        static let tapHitSlop: CGFloat = 11
    }

    let text: String
    var variant: ZappChipVariant = .muted
    var dotColor: ZappColors?
    var leadingIcon: Image?
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) {
                chip
                    .padding(.vertical, Constants.tapHitSlop)
                    .contentShape(Rectangle())
                    .padding(.vertical, -Constants.tapHitSlop)
            }
            .buttonStyle(.zappPress)
            .accessibilityLabel(text)
        } else {
            chip
        }
    }

    private var chip: some View {
        HStack(spacing: Constants.spacing) {
            if let dotColor {
                Rectangle()
                    .fill(dotColor.color(colorScheme))
                    .frame(width: Constants.dotSize, height: Constants.dotSize)
            }

            if let leadingIcon {
                leadingIcon
                    .zImage(width: Constants.iconSize, height: Constants.iconSize, style: fg)
            }

            Text(text)
                .zappFont(.chip, style: fg)
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.vertical, Constants.verticalPadding)
        .background(bg.color(colorScheme))
        .overlay {
            if let border {
                Rectangle()
                    .strokeBorder(border.color(colorScheme), lineWidth: 1)
            }
        }
    }

    private var bg: ZappColors {
        switch variant {
        case .muted: return .chipBg
        case .success: return .successSoft
        case .accent: return .accentSoft
        case .danger: return .dangerSoft
        case .outlined: return .surfaceAlt
        }
    }

    private var fg: ZappColors {
        switch variant {
        case .muted, .outlined: return .textMuted
        case .success: return .success
        case .accent: return .accentText
        case .danger: return .danger
        }
    }

    private var border: ZappColors? {
        variant == .outlined ? .border : nil
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        ZappStatusChip(text: "Muted")
        ZappStatusChip(text: "Online", variant: .success, dotColor: .success)
        ZappStatusChip(text: "Pending", variant: .accent)
        ZappStatusChip(text: "Failed", variant: .danger)
        ZappStatusChip(text: "Copy key", variant: .outlined, leadingIcon: Asset.Assets.copy.image) { }
    }
    .padding()
    .applyScreenBackground()
}
