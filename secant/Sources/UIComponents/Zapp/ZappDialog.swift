//
//  ZappDialog.swift
//  Zapp
//

import SwiftUI
import UIKit

private enum ZappDialogConstants {
    static let scrimOpacity: CGFloat = 0.6
    static let horizontalInset: CGFloat = 24
    static let maxHeightFraction: CGFloat = 0.8
}

/// Sharp-rectangle modal panel over a scrim, matching the geometry of the Android dialogs.
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
            Color.black
                .opacity(Constants.scrimOpacity)
                .ignoresSafeArea()
                .onTapGesture { onScrimTap?() }

            VStack(alignment: .leading, spacing: Design.Spacing._md) {
                content
            }
            .padding(Design.Spacing._lg)
            .frame(maxHeight: UIScreen.main.bounds.height * Constants.maxHeightFraction)
            .background(ZappColors.surface.color(colorScheme))
            .overlay(
                Rectangle()
                    .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
            )
            .padding(.horizontal, Constants.horizontalInset)
        }
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
            }
        }
}
