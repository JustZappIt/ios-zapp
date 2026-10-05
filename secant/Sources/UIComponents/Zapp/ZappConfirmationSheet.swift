// SPDX-License-Identifier: MIT OR Apache-2.0

import SwiftUI

/// What a `ZappConfirmationSheet` asks. Android's `ZappConfirmationState`, minus the callbacks,
/// which the presenting modifier takes so the value stays `Equatable` for TCA state.
struct ZappConfirmation: Equatable {
    let title: String
    let message: String
    let confirmTitle: String
    /// Nil hides the Ghost button; the scrim and the handle still dismiss.
    var cancelTitle: String?
    /// Danger instead of Primary for the confirm button.
    var isDestructive = false
}

/// The Zapp confirmation sheet, as Android's `ZappConfirmationBottomSheet`: a drag handle, a
/// centred title and message, then a Primary (or Danger) `ZappButton` over a Ghost one, on the
/// `surface` colour above the `overlay` scrim.
///
/// Like Android, the panel's top corners are rounded to 20pt and the handle is a capsule: the one
/// rounded surface in an otherwise square UI. The handle is the Zapp one, not the system indicator,
/// so it reads the same on every iOS version.
struct ZappConfirmationSheet: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let handleAreaHeight: CGFloat = 40
        static let handleTop: CGFloat = 8
        static let handleSize = CGSize(width: 42, height: 5)
        static let topCornerRadius: CGFloat = 20
        static let horizontalPadding: CGFloat = 24
        static let gapSmall: CGFloat = 8
        static let gapLarge: CGFloat = 20
        static let titleStyle = ZappTextStyle(weight: .semiBold, size: 18, lineHeight: 24, tracking: -0.3)
    }

    let confirmation: ZappConfirmation
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(ZappColors.borderStrong.color(colorScheme))
                .frame(width: Constants.handleSize.width, height: Constants.handleSize.height)
                .padding(.top, Constants.handleTop)
                .frame(maxWidth: .infinity, minHeight: Constants.handleAreaHeight, alignment: .top)
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                Text(confirmation.title)
                    .zappFont(Constants.titleStyle, style: ZappColors.text)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, Constants.gapLarge)

                Text(confirmation.message)
                    .zappFont(.body, style: ZappColors.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Constants.gapSmall)

                ZappButton(
                    title: confirmation.confirmTitle,
                    variant: confirmation.isDestructive ? .danger : .primary,
                    action: onConfirm
                )
                .padding(.top, Constants.gapLarge)

                if let cancelTitle = confirmation.cancelTitle {
                    ZappButton(title: cancelTitle, variant: .ghost, action: onCancel)
                        .padding(.top, Constants.gapSmall)
                }
            }
            .padding(.horizontal, Constants.horizontalPadding)
            .padding(.bottom, Constants.gapLarge)
        }
        .frame(maxWidth: .infinity)
        .background(
            TopRoundedRectangle(radius: Constants.topCornerRadius)
                .fill(ZappColors.surface.color(colorScheme))
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

private struct ZappConfirmationSheetModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    /// Past this, a downward drag on the panel dismisses it.
    private static let dismissDragDistance: CGFloat = 80

    let confirmation: ZappConfirmation?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var dragOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack(alignment: .bottom) {
                    if let confirmation {
                        ZappColors.overlay.color(colorScheme)
                            .ignoresSafeArea()
                            .onTapGesture(perform: onCancel)
                            .accessibilityHidden(true)
                            .transition(.opacity)

                        ZappConfirmationSheet(confirmation: confirmation, onConfirm: onConfirm, onCancel: onCancel)
                            .offset(y: dragOffset)
                            .gesture(dismissDrag)
                            .transition(.move(edge: .bottom))
                            .accessibilityAddTraits(.isModal)
                            .accessibilityAction(.escape, onCancel)
                    }
                }
                .animation(ZappMotion.content, value: confirmation)
            }
            .onChange(of: confirmation) { _ in dragOffset = 0 }
    }

    private var dismissDrag: some Gesture {
        DragGesture()
            .onChanged { dragOffset = max(0, $0.translation.height) }
            .onEnded { value in
                if value.translation.height > Self.dismissDragDistance {
                    onCancel()
                } else {
                    withAnimation(ZappMotion.state) { dragOffset = 0 }
                }
            }
    }
}

extension View {
    /// Presents a `ZappConfirmationSheet` over this view while `confirmation` is non-nil — the Zapp
    /// replacement for a system `.alert` confirmation. Stays inside the presenter's tree, like
    /// `ZappDialog`, so the overlay token can be the scrim.
    func zappConfirmationSheet(
        _ confirmation: ZappConfirmation?,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        modifier(ZappConfirmationSheetModifier(confirmation: confirmation, onConfirm: onConfirm, onCancel: onCancel))
    }
}

#Preview {
    Color.clear
        .applyScreenBackground()
        .zappConfirmationSheet(
            ZappConfirmation(
                title: "Leave group?",
                message: "You will stop receiving messages from this group.",
                confirmTitle: "Leave",
                cancelTitle: "Cancel",
                isDestructive: true
            ),
            onConfirm: { },
            onCancel: { }
        )
}
