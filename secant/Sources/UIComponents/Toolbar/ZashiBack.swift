//
//  ZashiBack.swift
//
//
//  Created by Lukáš Korba on 04.10.2023.
//

import SwiftUI

/// Zapp puts back at the BOTTOM-LEFT, in a dock, never in a top app bar.
///
/// Rewritten in place rather than replaced with a `zappBack()` of our own: upstream funnels all 57
/// screens through this one modifier, so overriding it here relocates every back button at once AND
/// makes any screen we later merge from upstream conform automatically. A parallel modifier would
/// leave newly-merged screens silently reintroducing a top-bar back button.
///
/// A screen with a primary CTA passes it through `primaryAction:` so the dock renders one row — back
/// left, CTA right, as on Android. With no CTA the dock stays chrome-free (`ZappBottomActionBar`
/// switches on `PrimaryAction.self == EmptyView.self`).
struct ZashiBackModifier<PrimaryAction: View>: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    let disabled: Bool
    let hidden: Bool
    let invertedColors: Bool
    let customDismiss: (() -> Void)?
    let primaryAction: PrimaryAction

    func body(content: Content) -> some View {
        if hidden {
            content
                .navigationBarBackButtonHidden(true)
        } else {
            content
                .navigationBarBackButtonHidden(true)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ZappBottomActionBar(
                        onBack: navigateBack,
                        backTint: invertedColors ? .bg : .text,
                        isBackEnabled: !disabled
                    ) {
                        primaryAction
                    }
                }
                .zappSwipeBack(isEnabled: !disabled, action: navigateBack)
        }
    }

    private func navigateBack() {
        if let customDismiss {
            customDismiss()
        } else {
            dismiss()
        }
    }
}

private struct ZappInteractiveBackModifier: ViewModifier {
    private enum Constants {
        static let activationWidth: CGFloat = 24
        static let completionProgress: CGFloat = 0.5
        static let minimumFlickProgress: CGFloat = 0.08
        static let settleDuration: TimeInterval = 0.2
    }

    @State private var horizontalOffset: CGFloat = 0
    @State private var isTracking = false
    @State private var isCompleting = false
    @State private var completionTask: Task<Void, Never>?

    let isEnabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            content
                .offset(x: horizontalOffset)
                .contentShape(Rectangle())
                .simultaneousGesture(edgeSwipeGesture(containerWidth: proxy.size.width))
        }
        .onDisappear {
            completionTask?.cancel()
        }
    }

    private func edgeSwipeGesture(containerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                guard !isCompleting else { return }

                if !isTracking {
                    guard beginsBackSwipe(value) else { return }
                    isTracking = true
                }

                horizontalOffset = max(0, value.translation.width)
            }
            .onEnded { value in
                guard isTracking else { return }
                isTracking = false

                if shouldComplete(value, containerWidth: containerWidth) {
                    completeSwipe(containerWidth: containerWidth)
                } else {
                    cancelSwipe()
                }
            }
    }

    private func beginsBackSwipe(_ value: DragGesture.Value) -> Bool {
        isEnabled
            && value.startLocation.x <= Constants.activationWidth
            && value.translation.width > 0
            && abs(value.translation.width) > abs(value.translation.height)
    }

    private func shouldComplete(
        _ value: DragGesture.Value,
        containerWidth: CGFloat
    ) -> Bool {
        guard containerWidth > 0 else { return false }

        let progress = horizontalOffset / containerWidth
        let predictedProgress = max(0, value.predictedEndTranslation.width) / containerWidth

        return progress >= Constants.completionProgress
            || (progress >= Constants.minimumFlickProgress
                && predictedProgress >= Constants.completionProgress)
    }

    private func cancelSwipe() {
        withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.9)) {
            horizontalOffset = 0
        }
    }

    private func completeSwipe(containerWidth: CGFloat) {
        isCompleting = true

        withAnimation(.easeOut(duration: Constants.settleDuration)) {
            horizontalOffset = containerWidth
        }

        completionTask?.cancel()
        completionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Constants.settleDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }

            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                action()
                horizontalOffset = 0
            }
            isCompleting = false
        }
    }
}

extension View {
    func zappSwipeBack(
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        modifier(ZappInteractiveBackModifier(isEnabled: isEnabled, action: action))
    }

    func zashiBack(
        _ disabled: Bool = false,
        hidden: Bool = false,
        invertedColors: Bool = false,
        customDismiss: (() -> Void)? = nil
    ) -> some View {
        modifier(
            ZashiBackModifier<EmptyView>(
                disabled: disabled,
                hidden: hidden,
                invertedColors: invertedColors,
                customDismiss: customDismiss,
                primaryAction: EmptyView()
            )
        )
    }

    /// The dock with a CTA in it: back left, action right.
    ///
    /// `primaryAction` is deliberately NOT the last parameter. Swift binds a bare trailing closure to
    /// the LAST closure-typed argument, so putting the `@ViewBuilder` last would make every one of the
    /// 57 existing `zashiBack { ... }` call sites silently rebind their `customDismiss` into this slot
    /// — yielding a dock whose back button does nothing and whose CTA is the old dismiss closure.
    /// Keeping it here means the plain overload still wins for those call sites, untouched.
    func zashiBack<PrimaryAction: View>(
        _ disabled: Bool = false,
        hidden: Bool = false,
        invertedColors: Bool = false,
        @ViewBuilder primaryAction: () -> PrimaryAction,
        customDismiss: (() -> Void)? = nil
    ) -> some View {
        modifier(
            ZashiBackModifier(
                disabled: disabled,
                hidden: hidden,
                invertedColors: invertedColors,
                customDismiss: customDismiss,
                primaryAction: primaryAction()
            )
        )
    }

    /// Back-left with an optional CTA-right: screens whose CTA exists only in some states pass
    /// `hasPrimaryAction: false` for the rest and get a chrome-free back button, not an empty bar.
    @ViewBuilder
    func zashiBack<PrimaryAction: View>(
        hasPrimaryAction: Bool,
        _ disabled: Bool = false,
        hidden: Bool = false,
        invertedColors: Bool = false,
        @ViewBuilder primaryAction: () -> PrimaryAction,
        customDismiss: (() -> Void)? = nil
    ) -> some View {
        if hasPrimaryAction {
            zashiBack(disabled, hidden: hidden, invertedColors: invertedColors, primaryAction: primaryAction, customDismiss: customDismiss)
        } else {
            zashiBack(disabled, hidden: hidden, invertedColors: invertedColors, customDismiss: customDismiss)
        }
    }
}
