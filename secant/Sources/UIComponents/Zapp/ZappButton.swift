//
//  ZappButton.swift
//  Zapp
//

import SwiftUI

enum ZappButtonVariant {
    case primary
    case secondary
    case ghost
    case danger
    case accentGhost
}

struct ZappButton: View {
    enum Size {
        case regular
        case compact
    }

    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let minHeight: CGFloat = 52
        static let horizontalPadding: CGFloat = 18
        static let verticalPadding: CGFloat = 14
        static let iconSize: CGFloat = 18
        static let iconSpacing: CGFloat = 8
        static let disabledOpacity: CGFloat = 0.45
    }

    let title: String
    var variant: ZappButtonVariant = .primary
    var isEnabled = true
    var isLoading = false
    var size: Size = .regular
    var leadingIcon: Image?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Constants.iconSpacing) {
                if isLoading {
                    ProgressView()
                        .tint(fg.color(colorScheme))
                        .controlSize(.small)
                        .accessibilityHidden(true)
                } else if let leadingIcon {
                    leadingIcon
                        .zImage(width: Constants.iconSize, height: Constants.iconSize, style: fg)
                }

                Text(title)
                    .zappFont(size == .compact ? .buttonSmall : .button, style: fg)
            }
            .padding(.horizontal, size == .compact ? 12 : Constants.horizontalPadding)
            .padding(.vertical, size == .compact ? 6 : Constants.verticalPadding)
            .frame(maxWidth: size == .regular ? .infinity : nil)
            .frame(minHeight: size == .regular ? Constants.minHeight : nil)
            .background(bg)
            .animation(ZappMotion.content, value: isEnabled)
            .overlay {
                if let borderCol {
                    Rectangle()
                        .strokeBorder(borderCol.color(colorScheme), lineWidth: 1)
                }
            }
            .opacity(dimsWhenDisabled ? Constants.disabledOpacity : 1)
            .frame(minWidth: size == .compact ? 48 : nil, minHeight: size == .compact ? 48 : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.zappPress)
        .disabled(!isEnabled || isLoading)
        .accessibilityLabel(title)
    }

    // Primary disabled swaps to a flat surfaceAlt/textSubtle pair; the other variants dim instead.
    private var dimsWhenDisabled: Bool {
        !isEnabled && !isLoading && variant != .primary
    }

    private var bg: Color {
        switch variant {
        case .primary: return (isEnabled || isLoading ? ZappColors.accent : ZappColors.surfaceAlt).color(colorScheme)
        case .secondary: return ZappColors.surfaceAlt.color(colorScheme)
        case .ghost, .accentGhost: return .clear
        case .danger: return ZappColors.dangerSoft.color(colorScheme)
        }
    }

    private var fg: ZappColors {
        switch variant {
        case .primary: return isEnabled || isLoading ? .onAccent : .textSubtle
        case .secondary, .ghost: return .text
        case .danger: return .danger
        case .accentGhost: return .accent
        }
    }

    private var borderCol: ZappColors? {
        switch variant {
        case .primary, .secondary, .danger: return nil
        case .ghost: return .border
        case .accentGhost: return .accent
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        ZappButton(title: "Primary") { }
        ZappButton(title: "Primary disabled", isEnabled: false) { }
        ZappButton(title: "Secondary", variant: .secondary) { }
        ZappButton(title: "Ghost", variant: .ghost) { }
        ZappButton(title: "Danger", variant: .danger) { }
        ZappButton(title: "Accent ghost", variant: .accentGhost) { }
    }
    .padding()
    .applyScreenBackground()
}
