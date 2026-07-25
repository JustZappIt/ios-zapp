//
//  ChatTermsView.swift
//  Zapp
//

import SwiftUI

/// The messaging terms gate, mirroring `ChatTermsDialog.kt`.
///
/// Android presents a Material `AlertDialog` with a scrolling body; iOS presents the same content
/// as a sheet, because the guidelines are far too long for a native alert. Dismissing the sheet is
/// the analogue of Android's `onDismissRequest`, which declines.
struct ChatTermsView: View {
    @Environment(\.colorScheme) private var colorScheme

    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(String(localizable: .chatTermsTitle))
                        .zappFont(.sectionTitle, style: ZappColors.text)

                    Spacer().frame(height: Design.Spacing._xl)

                    Text(String(localizable: .chatTermsIntro))
                        .zappFont(.body, style: ZappColors.text)

                    Spacer().frame(height: Design.Spacing._lg)

                    Text(String(localizable: .chatTermsGuidelinesHeading))
                        .zappFont(Self.headingStyle, style: ZappColors.text)

                    Spacer().frame(height: Design.Spacing._md)

                    Text(String(localizable: .chatTermsBody))
                        .zappFont(.caption, style: ZappColors.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Design.Spacing._xl)
                .padding(.top, Design.Spacing._3xl)
                .padding(.bottom, Design.Spacing._xl)
            }

            VStack(spacing: Design.Spacing._md) {
                ZappButton(title: String(localizable: .chatTermsAccept), action: onAccept)

                ZappButton(title: String(localizable: .chatTermsDecline), variant: .ghost, action: onDecline)
            }
            .padding(.horizontal, Design.Spacing._xl)
            .padding(.bottom, Design.Spacing._3xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ZappColors.bg.color(colorScheme))
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    /// Android bolds the guidelines heading on top of `typography.body`.
    private static var headingStyle: ZappTextStyle {
        ZappTextStyle(
            weight: .bold,
            size: ZappTextStyle.body.size,
            lineHeight: ZappTextStyle.body.lineHeight,
            tracking: ZappTextStyle.body.tracking
        )
    }
}

#Preview {
    ChatTermsView(onAccept: { }, onDecline: { })
}
