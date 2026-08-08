//
//  ZappSearchField.swift
//  Zapp
//

import SwiftUI

/// Search icon, field, and a clear button once there is something to clear.
struct ZappSearchField: View {
    private enum Constants {
        static let iconSize: CGFloat = 16
        static let clearSize: CGFloat = 12
        /// Lifts the 12pt glyph to a 44pt target without growing the field, as `ZappSegmentedSelector` does.
        static let clearHitSlop: CGFloat = 16
    }

    @Environment(\.colorScheme) private var colorScheme

    let placeholder: String

    @Binding var text: String

    let onClear: () -> Void

    var body: some View {
        HStack(spacing: Design.Spacing._sm) {
            Asset.Assets.Icons.search.image
                .zImage(width: Constants.iconSize, height: Constants.iconSize, style: ZappColors.textSubtle)

            TextField(placeholder, text: $text)
                .zappFont(.body, style: ZappColors.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !text.isEmpty {
                Button(action: onClear) {
                    Asset.Assets.Icons.xClose.image
                        .zImage(width: Constants.clearSize, height: Constants.clearSize, style: ZappColors.textSubtle)
                        .padding(Constants.clearHitSlop)
                        .contentShape(Rectangle())
                        .padding(-Constants.clearHitSlop)
                }
                .buttonStyle(.zappPress)
                .accessibilityLabel(String(localizable: .generalClear))
            }
        }
        .padding(.horizontal, Design.Spacing._md)
        .padding(.vertical, Design.Spacing._lg)
        .background(ZappColors.surfaceInput.color(colorScheme))
        .overlay {
            Rectangle()
                .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
        }
    }
}
