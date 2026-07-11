//
//  ZappComponents.swift
//  Zapp
//
//  Zapp fork: iOS ports of the android-zapp shell components
//  (`ui-design-lib/.../component/zapp/ZappComponents.kt`). Visual spec values
//  (sizes, paddings, weights) mirror the Android implementations 1:1.
//

import SwiftUI

// MARK: - ZappScreenHeader

/// Android `ZappScreenHeader`: screen title row with optional right accessory.
struct ZappScreenHeader<Right: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    @ViewBuilder let right: Right

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .zFont(.semiBold, size: 24, color: ZappColor.text(colorScheme))
                .lineLimit(1)

            Spacer(minLength: 0)

            right
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(ZappColor.surface(colorScheme))
    }
}

extension ZappScreenHeader where Right == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

// MARK: - ZappSectionLabel

/// Android `ZappSectionLabel`: uppercase group label in muted text.
struct ZappSectionLabel: View {
    @Environment(\.colorScheme) private var colorScheme

    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.custom(FontFamily.Inter.black.name, size: 11))
            .kerning(1.8)
            .foregroundColor(ZappColor.textMuted(colorScheme))
    }
}

// MARK: - ZappStatusChip

enum ZappChipVariant {
    case muted
    case success
    case accent
    case danger
}

/// Android `ZappStatusChip`: sharp-cornered status chip with optional leading dot.
struct ZappStatusChip: View {
    @Environment(\.colorScheme) private var colorScheme

    let text: String
    var variant: ZappChipVariant = .muted
    var showDot = true

    private var background: Color {
        switch variant {
        case .success: return ZappColor.successSoft(colorScheme)
        case .accent: return ZappColor.accentSoft(colorScheme)
        case .danger: return ZappColor.dangerSoft(colorScheme)
        case .muted: return ZappColor.chipBg(colorScheme)
        }
    }

    private var foreground: Color {
        switch variant {
        case .success: return ZappColor.success(colorScheme)
        case .accent: return ZappColor.accentText(colorScheme)
        case .danger: return ZappColor.danger(colorScheme)
        case .muted: return ZappColor.textMuted(colorScheme)
        }
    }

    private var dotColor: Color {
        switch variant {
        case .success: return ZappColor.success(colorScheme)
        case .accent: return ZappColor.accent(colorScheme)
        case .danger: return ZappColor.danger(colorScheme)
        case .muted: return ZappColor.textSubtle(colorScheme)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            if showDot {
                Rectangle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
            }

            Text(text)
                .font(.custom(FontFamily.Inter.black.name, size: 11))
                .foregroundColor(foreground)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(background)
    }
}

// MARK: - ZappRow

/// Android `ZappRow`: settings-style row with icon box, title/subtitle, chevron.
struct ZappRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    var subtitle: String?
    var icon: Image?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                if let icon {
                    ZStack {
                        Rectangle()
                            .fill(ZappColor.accentSoft(colorScheme))
                            .frame(width: 36, height: 36)

                        icon
                            .zImage(size: 18, color: ZappColor.accentText(colorScheme))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.custom(FontFamily.Inter.black.name, size: 14))
                        .foregroundColor(ZappColor.text(colorScheme))
                        .lineLimit(1)

                    if let subtitle {
                        Text(subtitle)
                            .zFont(size: 12, color: ZappColor.textMuted(colorScheme))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 0)

                Asset.Assets.chevronRight.image
                    .zImage(size: 18, color: ZappColor.textSubtle(colorScheme))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
    }
}

/// Android `ZappRowDivider`: hairline divider, inset under the title column.
struct ZappRowDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var inset = false

    var body: some View {
        Rectangle()
            .fill(ZappColor.border(colorScheme))
            .frame(height: 1)
            .padding(.leading, inset ? 68 : 18)
            .padding(.trailing, 18)
    }
}

// MARK: - ZappSegmentedSelector

/// Android `ZappSegmentedSelector`: bg-filled selected segment on a bordered
/// surface container - used by the balance-card period switcher.
struct ZappSegmentedSelector: View {
    @Environment(\.colorScheme) private var colorScheme

    let options: [String]
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let isSelected = index == selectedIndex

                Button {
                    onSelect(index)
                } label: {
                    Text(options[index])
                        .zFont(
                            size: 12,
                            color: isSelected
                            ? ZappColor.text(colorScheme)
                            : ZappColor.textMuted(colorScheme)
                        )
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(isSelected ? ZappColor.bg(colorScheme) : Color.clear)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(3)
        .background(ZappColor.surface(colorScheme))
        .overlay {
            Rectangle()
                .stroke(ZappColor.border(colorScheme), lineWidth: 1)
        }
    }
}

// MARK: - ZappBottomActionBar

/// Android `ZappBackButton`: 48pt touch target, 20pt arrow, text tint.
struct ZappBackButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.left")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(ZappColor.text(colorScheme))
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(String(localizable: .generalBack))
    }
}

/// Android `ZappBottomActionBar`: back always bottom-left. With a primary
/// action the bar gets a bordered surface; a lone back stays chrome-free.
/// Insets and margin are applied before background/border so the border
/// floats above the home-indicator inset, per the Android idiom.
struct ZappBottomActionBar<Primary: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let onBack: () -> Void
    @ViewBuilder let primaryAction: Primary

    private var hasPrimary: Bool { Primary.self != EmptyView.self }

    var body: some View {
        HStack(alignment: .center) {
            ZappBackButton(action: onBack)

            Spacer(minLength: 12)

            primaryAction
        }
        .padding(12)
        .frame(minHeight: 52)
        .background(hasPrimary ? ZappColor.surface(colorScheme) : Color.clear)
        .overlay {
            if hasPrimary {
                Rectangle()
                    .stroke(ZappColor.border(colorScheme), lineWidth: 1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }
}

extension ZappBottomActionBar where Primary == EmptyView {
    init(onBack: @escaping () -> Void) {
        self.init(onBack: onBack) { EmptyView() }
    }
}

// MARK: - ZappFab

/// Android `ZappFab`: sharp square accent FAB with a 1pt border and flat shadow.
struct ZappFab: View {
    @Environment(\.colorScheme) private var colorScheme

    let icon: Image
    let accessibilityLabel: String
    var size: CGFloat = 56
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Rectangle()
                    .fill(ZappColor.accent(colorScheme))
                    .frame(width: size, height: size)
                    .overlay {
                        Rectangle()
                            .stroke(ZappColor.border(colorScheme), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)

                icon
                    .zImage(size: 22, color: ZappColor.onAccent(colorScheme))
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel(accessibilityLabel)
    }
}
