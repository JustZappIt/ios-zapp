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

/// Live back-swipe progress (0...1), reported up to `RootView` so it can parallax the screen behind.
struct SwipeBackProgressKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Routes the progress preference through `animatableData` so it interpolates on release rather than
/// jumping to the target `withAnimation` has already committed.
private struct SwipeBackProgressReporter: ViewModifier, Animatable {
    var progress: CGFloat

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.preference(key: SwipeBackProgressKey.self, value: min(1, max(0, progress)))
    }
}

/// Interactive edge-back: the screen tracks the finger from the left edge, then goes back past the
/// halfway point or on a flick, otherwise snaps back.
private struct ZappInteractiveBackModifier: ViewModifier {
    private enum Constants {
        static let edgeWidth: CGFloat = 30
        static let minimumDistance: CGFloat = 8
        static let completionProgress: CGFloat = 0.5
        static let minimumFlickProgress: CGFloat = 0.1
        static let settleDuration: TimeInterval = 0.2
        static let shadowMaxOpacity: CGFloat = 0.18
        static let shadowRadius: CGFloat = 10
    }

    @Environment(\.colorScheme) private var colorScheme

    @State private var containerWidth: CGFloat = 0
    @State private var horizontalOffset: CGFloat = 0
    @State private var isTracking = false
    @State private var isCompleting = false
    @State private var completionTask: Task<Void, Never>?

    let isEnabled: Bool
    let action: () -> Void

    private var progress: CGFloat {
        containerWidth > 0 ? min(1, max(0, horizontalOffset / containerWidth)) : 0
    }

    func body(content: Content) -> some View {
        content
            .offset(x: horizontalOffset)
            .shadow(
                color: ZappColors.shadow.color(colorScheme).opacity(Constants.shadowMaxOpacity * shadowStrength),
                radius: Constants.shadowRadius,
                x: -Constants.shadowRadius / 2
            )
            .background(widthReader)
            .contentShape(Rectangle())
            .simultaneousGesture(edgeSwipeGesture)
            .modifier(SwipeBackProgressReporter(progress: progress))
            .onDisappear {
                completionTask?.cancel()
            }
    }

    // No shadow at rest; fades in over the first few points as the screen lifts off the edge.
    private var shadowStrength: CGFloat {
        horizontalOffset <= 0 ? 0 : min(1, horizontalOffset / Constants.edgeWidth)
    }

    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { containerWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { newWidth in containerWidth = newWidth }
        }
    }

    private var edgeSwipeGesture: some Gesture {
        // `.global` space, not `.local`: local space moves with the view we offset, halving tracking.
        DragGesture(minimumDistance: Constants.minimumDistance, coordinateSpace: .global)
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

                if shouldComplete(value) {
                    completeSwipe()
                } else {
                    cancelSwipe()
                }
            }
    }

    private func beginsBackSwipe(_ value: DragGesture.Value) -> Bool {
        isEnabled
            && value.startLocation.x <= Constants.edgeWidth
            && value.translation.width > 0
            && abs(value.translation.width) > abs(value.translation.height)
    }

    private func shouldComplete(_ value: DragGesture.Value) -> Bool {
        guard containerWidth > 0 else { return false }

        let predictedProgress = max(0, value.predictedEndTranslation.width) / containerWidth

        return progress >= Constants.completionProgress
            || (progress >= Constants.minimumFlickProgress
                && predictedProgress >= Constants.completionProgress)
    }

    private func cancelSwipe() {
        withAnimation(ZappMotion.content) {
            horizontalOffset = 0
        }
    }

    private func completeSwipe() {
        isCompleting = true

        withAnimation(ZappMotion.content) {
            horizontalOffset = containerWidth
        }

        completionTask?.cancel()
        completionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Constants.settleDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }

            // Leave the offset at full width: `action()` unmounts the screen, so its removal plays
            // off-screen. Resetting to 0 would drop it back to center and flash it on the way out.
            action()
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
