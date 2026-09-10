//
//  ZappInputField.swift
//  Zapp
//
//  Ported from ZappInputField.kt. A bordered single-line field with optional leading
//  and trailing slots — the shape every Zapp form field takes on Android.
//

import SwiftUI

/// A form field carrying its own border, an optional leading glyph, and an optional trailing
/// action. The border thickens once there is content, which is the whole of Android's
/// filled-vs-empty affordance (`ZappInputField.kt:28-34`).
/// Swift forbids static stored properties inside a generic type, so these sit outside it and
/// come back in through a typealias — the same shape `ZappValueCard` uses.
enum ZappInputFieldConstants {
    /// Android pins the field to 52dp so one with a trailing action matches one without.
    /// `minHeight` rather than `height`: the field has to grow with Dynamic Type.
    static let minHeight: CGFloat = 52
    static let horizontalPadding: CGFloat = 14
    static let leadingGap: CGFloat = 10
    static let filledBorderWidth: CGFloat = 2
    static let emptyBorderWidth: CGFloat = 1
}

struct ZappInputField<Leading: View, Trailing: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    private typealias Constants = ZappInputFieldConstants

    let placeholder: String
    @Binding var text: String
    /// Long values — keys, addresses — are typed and pasted, never composed, so they get no
    /// autocorrect or autocapitalisation.
    var isVerbatim = false
    var accessibilityLabel: String?
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 0) {
            if Leading.self != EmptyView.self {
                leading()
                    .padding(.trailing, Constants.leadingGap)
            }

            field
                .frame(maxWidth: .infinity)

            trailing()
        }
        .padding(.leading, Constants.horizontalPadding)
        .padding(.trailing, hasTrailing ? 0 : Constants.horizontalPadding)
        .frame(minHeight: Constants.minHeight)
        .background(ZappColors.surfaceInput.color(colorScheme))
        .overlay {
            Rectangle().strokeBorder(
                text.isEmpty
                    ? ZappColors.border.color(colorScheme)
                    : ZappColors.borderStrong.color(colorScheme),
                lineWidth: text.isEmpty ? Constants.emptyBorderWidth : Constants.filledBorderWidth
            )
        }
    }

    /// The placeholder is drawn rather than handed to `TextField`, which offers no token-level
    /// control over its colour.
    private var field: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .zappFont(.body, style: ZappColors.textSubtle)
                    .lineLimit(1)
                    .allowsHitTesting(false)
            }

            TextField("", text: $text)
                .textFieldStyle(.plain)
                .zappFont(isVerbatim ? .mono : .body, style: ZappColors.text)
                .tint(ZappColors.accent.color(colorScheme))
                .textInputAutocapitalization(isVerbatim ? .never : .sentences)
                .autocorrectionDisabled(isVerbatim)
                .accessibilityLabel(accessibilityLabel ?? placeholder)
        }
    }

    private var hasTrailing: Bool {
        Trailing.self != EmptyView.self
    }
}

extension ZappInputField where Trailing == EmptyView {
    init(
        placeholder: String,
        text: Binding<String>,
        isVerbatim: Bool = false,
        accessibilityLabel: String? = nil,
        @ViewBuilder leading: @escaping () -> Leading
    ) {
        self.init(
            placeholder: placeholder,
            text: text,
            isVerbatim: isVerbatim,
            accessibilityLabel: accessibilityLabel,
            leading: leading,
            trailing: { EmptyView() }
        )
    }
}

extension ZappInputField where Leading == EmptyView, Trailing == EmptyView {
    init(
        placeholder: String,
        text: Binding<String>,
        isVerbatim: Bool = false,
        accessibilityLabel: String? = nil
    ) {
        self.init(
            placeholder: placeholder,
            text: text,
            isVerbatim: isVerbatim,
            accessibilityLabel: accessibilityLabel,
            leading: { EmptyView() },
            trailing: { EmptyView() }
        )
    }
}

/// The 44pt-square trailing action Android draws at 48dp — a scan button, most often.
struct ZappInputFieldAction: View {
    private enum ActionConstants {
        static let touchTarget: CGFloat = 44
        static let iconSize: CGFloat = 20
    }

    let icon: Image
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            icon
                .zImage(width: ActionConstants.iconSize, height: ActionConstants.iconSize, style: ZappColors.textSubtle)
                .frame(width: ActionConstants.touchTarget, height: ActionConstants.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.zappPress)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// The glyph Android puts at the head of a field: 18pt, in the subtle ink.
struct ZappInputFieldGlyph: View {
    private static let size: CGFloat = 18

    let icon: Image

    var body: some View {
        icon.zImage(width: Self.size, height: Self.size, style: ZappColors.textSubtle)
    }
}

#Preview {
    VStack(spacing: 12) {
        ZappInputField(placeholder: "Empty", text: .constant("")) {
            ZappInputFieldGlyph(icon: Asset.Assets.Icons.user.image)
        }

        ZappInputField(placeholder: "Filled", text: .constant("Ada Lovelace")) {
            ZappInputFieldGlyph(icon: Asset.Assets.Icons.user.image)
        }

        ZappInputField(
            placeholder: "With a trailing action",
            text: .constant(""),
            isVerbatim: true,
            leading: { ZappInputFieldGlyph(icon: Asset.Assets.Icons.key.image) },
            trailing: {
                ZappInputFieldAction(icon: Asset.Assets.Icons.qr.image, accessibilityLabel: "Scan") { }
            }
        )

        ZappInputField(placeholder: "No glyph", text: .constant(""))
    }
    .padding()
    .applyScreenBackground()
}
