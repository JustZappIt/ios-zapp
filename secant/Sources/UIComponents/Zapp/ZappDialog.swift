//
//  ZappDialog.swift
//  Zapp
//

import SwiftUI
import UIKit

private enum ZappDialogConstants {
    static let horizontalInset: CGFloat = 28
    static let padding: CGFloat = 24
    static let spacing: CGFloat = 16
    static let maxHeightFraction: CGFloat = 0.8
    static let buttonHeight: CGFloat = 48
    static let buttonSpacing: CGFloat = 12
    static let buttonStyle = ZappTextStyle(weight: .black, size: 15, lineHeight: 20)
}

/// Sharp-rectangle modal panel over the `overlay` scrim, with the geometry of Android's chat
/// `ConfirmDialog`: borderless `surface` panel, 24 padding, 16 between blocks, 28 from the edges.
///
/// Deliberately NOT a `sheet`/`fullScreenCover`: it stays inside the presenting view's own tree,
/// because on iOS a modal presentation can take the presenter's `onDisappear` with it — and the
/// chat profile hangs its secret-clearing on exactly that.
struct ZappDialog<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    private typealias Constants = ZappDialogConstants

    /// Nil for a dialog that must be dismissed through its own controls; the scrim swallows the
    /// tap either way.
    var onScrimTap: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            ZappColors.overlay.color(colorScheme)
                .ignoresSafeArea()
                .onTapGesture { onScrimTap?() }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Constants.spacing) {
                content
            }
            .padding(Constants.padding)
            .frame(maxHeight: UIScreen.main.bounds.height * Constants.maxHeightFraction)
            .background(ZappColors.surface.color(colorScheme))
            .padding(.horizontal, Constants.horizontalInset)
        }
        // Modal to VoiceOver as well as to the eye — a scrim the rotor walks straight past is
        // how someone reaches Delete identity from behind a dialog. `escape` is the two-finger
        // scrub, and is deliberately inert for a dialog that owns its own dismissal.
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { onScrimTap?() }
    }
}

/// The cancel / confirm pair along the bottom of a `ZappDialog`, as Android's `ConfirmDialog`:
/// two equal 48pt buttons side by side, cancel on `surfaceAlt`, confirm on the accent or, when
/// destructive, solid `danger` with `bg` text.
struct ZappDialogActions: View {
    @Environment(\.colorScheme) private var colorScheme

    private typealias Constants = ZappDialogConstants

    let cancelTitle: String
    let confirmTitle: String
    var isDestructive = true
    var isConfirmEnabled = true
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: Constants.buttonSpacing) {
            button(cancelTitle, background: .surfaceAlt, foreground: .text, action: onCancel)
            button(
                confirmTitle,
                background: isDestructive ? .danger : .accent,
                foreground: isDestructive ? .bg : .onAccent,
                action: onConfirm
            )
            .disabled(!isConfirmEnabled)
            .opacity(isConfirmEnabled ? 1 : 0.45)
        }
    }

    private func button(
        _ title: String,
        background: ZappColors,
        foreground: ZappColors,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .zappFont(Constants.buttonStyle, style: foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: Constants.buttonHeight)
                .background(background.color(colorScheme))
        }
        .buttonStyle(.zappHighlight(tint: foreground))
        .accessibilityLabel(title)
    }
}

#Preview {
    Color.gray
        .overlay {
            ZappDialog {
                Text("Title")
                    .zappFont(.sectionTitle, style: ZappColors.text)

                Text("A short explanation of what this dialog is asking for.")
                    .zappFont(.body, style: ZappColors.textMuted)

                ZappDialogActions(cancelTitle: "Cancel", confirmTitle: "Delete", onCancel: { }, onConfirm: { })
            }
        }
}
